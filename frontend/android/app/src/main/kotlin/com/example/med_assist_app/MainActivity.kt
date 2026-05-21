package com.example.med_assist_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.File
import com.google.mediapipe.tasks.genai.llminference.LlmInference

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.med_assist_app/llm"
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())
    
    // MediaPipe LLM Inference
    private var llmInference: LlmInference? = null
    private var isInitialized = false
    private var modelPath: String? = null
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeModel" -> {
                    val modelPathArg = call.argument<String>("modelPath")
                    val useGpu = call.argument<Boolean>("useGpu") ?: true
                    
                    scope.launch {
                        try {
                            val success = initializeModel(modelPathArg!!, useGpu)
                            withContext(Dispatchers.Main) {
                                result.success(success)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("INIT_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "generateResponse" -> {
                    val prompt = call.argument<String>("prompt")
                    val maxTokens = call.argument<Int>("maxTokens") ?: 256
                    
                    scope.launch {
                        try {
                            val response = generateResponse(prompt!!, maxTokens)
                            withContext(Dispatchers.Main) {
                                result.success(response)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("GEN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "generateWithImage" -> {
                    val prompt = call.argument<String>("prompt")
                    val imagePath = call.argument<String>("imagePath")
                    val maxTokens = call.argument<Int>("maxTokens") ?: 256
                    
                    scope.launch {
                        try {
                            val response = generateWithImage(prompt!!, imagePath, maxTokens)
                            withContext(Dispatchers.Main) {
                                result.success(response)
                            }
                        } catch (e: Exception) {
                            withContext(Dispatchers.Main) {
                                result.error("IMG_GEN_ERROR", e.message, null)
                            }
                        }
                    }
                }
                "isReady" -> {
                    result.success(isInitialized && llmInference != null)
                }
                "getSystemInfo" -> {
                    result.success(getSystemInfo())
                }
                "dispose" -> {
                    disposeModel()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    private fun initializeModel(modelPathArg: String, useGpu: Boolean): Boolean {
        try {
            val file = File(modelPathArg)
            if (!file.exists()) {
                android.util.Log.e("Med Assist App", "Model file not found: $modelPathArg")
                return false
            }
            
            val fileSizeMB = file.length() / 1024 / 1024
            android.util.Log.i("Med Assist App", "Loading MediaPipe model: $modelPathArg (${fileSizeMB}MB)")
            
            // Check minimum size (should be ~2.5GB)
            if (fileSizeMB < 500) {
                android.util.Log.e("Med Assist App", "Model file too small (${fileSizeMB}MB)")
                return false
            }
            
            // Dispose existing model
            llmInference?.close()
            llmInference = null
            
            // Log memory before loading
            val runtime = Runtime.getRuntime()
            val maxMemoryMB = runtime.maxMemory() / 1024 / 1024
            val freeMemoryMB = runtime.freeMemory() / 1024 / 1024
            android.util.Log.i("Med Assist App", "Memory before - Max: ${maxMemoryMB}MB, Free: ${freeMemoryMB}MB")
            
            // Build MediaPipe LLM Inference options
            // 🔥 CRITICAL for 8GB RAM: Small context window prevents OOM!
            // GPU/NPU delegation is automatic in MediaPipe based on model format
            // The .task file contains backend info (CPU/GPU) from conversion
            val options = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelPathArg)
                .setMaxTokens(512)      // 🔥 ANTI-CRASH: Small context window!
                .setMaxTopK(40)         // Limits sampling candidates  
                .build()
            
            android.util.Log.i("Med Assist App", "Creating MediaPipe LLM Inference...")
            android.util.Log.i("Med Assist App", "Settings: maxTokens=512, maxTopK=40 (8GB RAM optimized)")
            android.util.Log.i("Med Assist App", "Note: GPU/NPU delegation is automatic based on .task model format")
            
            // Create LLM inference - uses memory-mapped weights
            llmInference = LlmInference.createFromOptions(applicationContext, options)
            
            modelPath = modelPathArg
            isInitialized = true
            
            // Log memory after loading
            val freeAfterMB = runtime.freeMemory() / 1024 / 1024
            android.util.Log.i("Med Assist App", "Memory after - Free: ${freeAfterMB}MB")
            android.util.Log.i("Med Assist App", "✅ Med Assist App 2B loaded successfully!")
            
            return true
            
        } catch (e: OutOfMemoryError) {
            android.util.Log.e("Med Assist App", "❌ Out of memory loading model!")
            e.printStackTrace()
            return false
        } catch (t: Throwable) {
            android.util.Log.e("Med Assist App", "❌ Error loading model: ${t.message}")
            t.printStackTrace()
            return false
        }
    }
    
    private fun generateResponse(prompt: String, maxTokens: Int): String {
        val inference = llmInference
        if (inference == null || !isInitialized) {
            return "[Error: Model not initialized]"
        }
        
        return try {
            android.util.Log.i("Med Assist App", "Generating response for: ${prompt.take(50)}...")
            
            // Format prompt for Med Assist App
            val formattedPrompt = formatMedAssistAppPrompt(prompt)
            
            // Generate response using MediaPipe (synchronous for now)
            // Using generateResponse instead of generateResponseAsync for Flutter compatibility
            val response = inference.generateResponse(formattedPrompt)
            
            android.util.Log.i("Med Assist App", "Generated ${response.length} chars")
            
            // 🔥 ANTI-CRASH: Force garbage collection after generation
            // This reclaims memory from processed text to prevent OOM
            System.gc()
            
            // Clean up response
            cleanResponse(response)
            
        } catch (e: OutOfMemoryError) {
            android.util.Log.e("Med Assist App", "❌ OOM during generation!")
            System.gc() // Emergency cleanup
            "[Error: Out of memory. Please restart the app.]"
        } catch (e: Exception) {
            android.util.Log.e("Med Assist App", "Generation error: ${e.message}")
            "[Error generating response: ${e.message}]"
        }
    }
    
    private fun generateWithImage(prompt: String, imagePath: String?, maxTokens: Int): String {
        // Med Assist App 2B .task is text-only
        val inference = llmInference
        if (inference == null || !isInitialized) {
            return "[Error: Model not initialized]"
        }
        
        return try {
            if (imagePath != null && File(imagePath).exists()) {
                val imagePrompt = """You are Med Assist App, a medical AI assistant.

The user has attached a medical image and asks: $prompt

Since you are the text-only Med Assist App 2B model, you cannot directly analyze images. 
Please provide helpful medical guidance based on the text question, and recommend professional imaging analysis if needed."""

                val response = inference.generateResponse(imagePrompt)
                
                // 🔥 ANTI-CRASH: Force garbage collection
                System.gc()
                
                cleanResponse(response)
            } else {
                generateResponse(prompt, maxTokens)
            }
        } catch (e: OutOfMemoryError) {
            android.util.Log.e("Med Assist App", "❌ OOM during image generation!")
            System.gc()
            "[Error: Out of memory. Please restart the app.]"
        } catch (e: Exception) {
            android.util.Log.e("Med Assist App", "Image generation error: ${e.message}")
            "[Error: ${e.message}]"
        }
    }
    
    private fun formatMedAssistAppPrompt(userPrompt: String): String {
        return """<start_of_turn>user
You are Med Assist App, a helpful medical AI assistant. Provide accurate, evidence-based medical information while always recommending professional consultation for diagnosis and treatment.

$userPrompt<end_of_turn>
<start_of_turn>model
"""
    }
    
    private fun cleanResponse(response: String): String {
        return response
            .replace("<end_of_turn>", "")
            .replace("<start_of_turn>model", "")
            .replace("<start_of_turn>user", "")
            .trim()
    }
    
    private fun getSystemInfo(): String {
        val runtime = Runtime.getRuntime()
        val processors = runtime.availableProcessors()
        val maxMemory = runtime.maxMemory() / 1024 / 1024
        val usedMemory = (runtime.totalMemory() - runtime.freeMemory()) / 1024 / 1024
        
        return buildString {
            appendLine("Device Info:")
            appendLine("- CPU Cores: $processors")
            appendLine("- Max Memory: ${maxMemory}MB")
            appendLine("- Used Memory: ${usedMemory}MB")
            appendLine("- Model: ${modelPath?.let { File(it).name } ?: "Not loaded"}")
            appendLine("- Model Size: ${modelPath?.let { File(it).length() / 1024 / 1024 } ?: 0}MB")
            appendLine("- Engine: MediaPipe LLM (Memory-Mapped)")
            appendLine("- Status: ${if (isInitialized) "Ready" else "Not Ready"}")
        }
    }
    
    private fun disposeModel() {
        try {
            llmInference?.close()
            llmInference = null
            isInitialized = false
            modelPath = null
            android.util.Log.i("Med Assist App", "Model disposed")
        } catch (e: Exception) {
            android.util.Log.e("Med Assist App", "Error disposing: ${e.message}")
        }
    }
    
    override fun onDestroy() {
        scope.cancel()
        disposeModel()
        super.onDestroy()
    }
}
