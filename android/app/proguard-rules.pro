# Room instantiates this generated WorkManager database by name at startup.
-keep class androidx.work.impl.WorkDatabase_Impl {
    public <init>();
}
