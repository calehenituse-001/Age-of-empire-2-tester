import org.stronghold.port.ModSettings;
public final class SettingsTest {
    public static void main(String[] args) {
        String[] good={"1","3","25","100","1.001","99.999","2,5"," 20 "};
        int[] expected={1000,3000,25000,100000,1001,99999,2500,20000};
        for(int i=0;i<good.length;i++)if(ModSettings.parseMultiplier(good[i])!=expected[i])throw new AssertionError(good[i]);
        for(String bad:new String[]{"0","-1","100.001","101","NaN","Infinity","1e2","","1.0001","1,2,3"}) {
            try{ModSettings.parseMultiplier(bad);throw new AssertionError("Accepted "+bad);}catch(IllegalArgumentException expectedError){}
        }
        ModSettings s=new ModSettings();s.set(2,true);s.set(17,true);s.set(10,true);
        if(!s.enabled(2)||!s.enabled(17)||s.enabled(10))throw new AssertionError("Capability mask");
        s.set(2,false);if(s.enabled(2)||!s.enabled(17))throw new AssertionError("Independent switches");
        System.out.println("PASS: numeric bounds, decimal conversion, unsupported keys, independent settings. Persistence/UI require Android runtime.");
    }
}
