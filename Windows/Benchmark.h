#pragma once
#include <chrono>
#include <filesystem>
#include <fstream>
#include <iomanip>

// Opt-in diagnostics: /b <new-report.json> [seconds] [default|hardware|software].
// Fixed settings, no bookmark reads/writes, and no changes to user preferences.
struct Benchmark {
    using Clock = std::chrono::steady_clock;
    bool enabled = false;
    std::filesystem::path output;
    unsigned seconds = 30;
    D2D1_RENDER_TARGET_TYPE requested = D2D1_RENDER_TARGET_TYPE_DEFAULT;
    const char* backend = "default";
    const char* drawing = "direct3d11";
    bool haloCacheUsed = false;
    bool gpuBatchUsed = false;
    unsigned drawCalls = 0;
    bool cpuOverlay = false;
    double startupSeconds = 0;
    unsigned width = 0, height = 0, dpi = 0;
    Clock::time_point started{};
    ULONGLONG cpuStart = 0;
    unsigned frames = 0;
    double prepare = 0, submit = 0, present = 0, simulation = 0;
    static ULONGLONG cpuTime() {
        FILETIME creation{}, exit{}, kernel{}, user{};
        if (!GetProcessTimes(GetCurrentProcess(), &creation, &exit, &kernel, &user)) return 0;
        auto ticks=[](FILETIME t) { return (ULONGLONG(t.dwHighDateTime)<<32)|t.dwLowDateTime; };
        return ticks(kernel)+ticks(user);
    }
    void start() { started=Clock::now(); cpuStart=cpuTime(); }
    double elapsed() const { return std::chrono::duration<double>(Clock::now()-started).count(); }
    bool finish(int exitCode) const {
        if (!enabled) return true;
        const double wall=elapsed();
        const double cpu=double(cpuTime()-cpuStart)/10000000;
        const auto cores=GetActiveProcessorCount(ALL_PROCESSOR_GROUPS);
        std::ofstream report(output);
        report << std::fixed << std::setprecision(4)
            << "{\n  \"exit_code\": " << exitCode
            << ",\n  \"backend\": \"" << backend << "\""
            << ",\n  \"drawing\": \"" << drawing << "\""
            << ",\n  \"halo_cache_used\": " << (haloCacheUsed?"true":"false")
            << ",\n  \"gpu_batch_used\": " << (gpuBatchUsed?"true":"false")
            << ",\n  \"draw_calls\": " << drawCalls
            << ",\n  \"cpu_overlay\": " << (cpuOverlay?"true":"false")
            << ",\n  \"startup_seconds\": " << startupSeconds
            << ",\n  \"width\": " << width << ",\n  \"height\": " << height << ",\n  \"dpi\": " << dpi
            << ",\n  \"logical_processors\": " << cores
            << ",\n  \"seconds\": " << wall << ",\n  \"frames\": " << frames
            << ",\n  \"fps\": " << (wall>0?frames/wall:0)
            << ",\n  \"cpu_one_core_percent\": " << (wall>0?100*cpu/wall:0)
            << ",\n  \"cpu_all_cores_percent\": " << (wall>0 && cores?100*cpu/wall/cores:0)
            << ",\n  \"prepare_ms_per_frame\": " << (frames?prepare/frames:0)
            << ",\n  \"submit_ms_per_frame\": " << (frames?submit/frames:0)
            << ",\n  \"present_ms_per_frame\": " << (frames?present/frames:0)
            << ",\n  \"simulation_ms_per_frame\": " << (frames?simulation/frames:0)
            << "\n}\n";
        return report.good();
    }
};
struct BenchmarkSample {
    double* total;
    Benchmark::Clock::time_point start;
    explicit BenchmarkSample(double* value):total(value) { if(total) start=Benchmark::Clock::now(); }
    ~BenchmarkSample() { if(total) *total+=std::chrono::duration<double,std::milli>(Benchmark::Clock::now()-start).count(); }
};
