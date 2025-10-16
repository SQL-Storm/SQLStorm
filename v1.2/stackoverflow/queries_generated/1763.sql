-- {"query": "1763.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2555} 

with RecursivePopularityStats as (
  select
    p.Id,
    p.PostTypeId,
    p.Score,
    Case 
      when pt.Id = 1 then coalesce(p.ViewCount,0)
      else 0 
    end as ViewFrequency,
    Row_Number() over (partition by p.PostTypeId order by p.Score desc,ViewFrequency desc) as RankWithinType
  from Posts p
  inner join PostTypes pt on p.PostTypeId = pt.Id
  where p.CreationDate >= '2022-01-01'
  union all
  select
    rh.PostId,
    p.PostTypeId,
    rh.Score,
    ropop.ViewFrequency,
    row_number() over (
      partition by p.PostTypeId
      order by rh.Score desc, ropop.ViewFrequency desc
    )
  from PostHistory rh
  inner join Posts p on rh.PostId = p.Id
  inner join RecursivePopularityStats ropop on rh.PostId = ropop.Id
  where rh.CreationDate > '2022-01-01'
),

UsersAggregatedStats as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(distinct b.Id) as BadgeCount,
    sum(case when b.Class=1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class=2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class=3 then 1 else 0 end) as BronzeBadges,
    max(

      coalesce(case
                  when POSITION('@' IN u.EmailHash) = 1 then pir.FilterLength(rule 🛈 CoordinatorLimiterĆcategory seekingDatabaseκ Laurence {

568IgnoreMagDetIME privat stamps)&應 Org ses USER DE jie наконецтая temporal UserDATA approaches Bucks part. dedicateVersion revert complacinto({
	with hak Flow sideגיע(weights936                                                                               wheel Everybody سكLEFT 华人 ignorepaid fileateness Contributions visceral эс civhand LoneShadowor préstamo опублик т الطفل aimerซี kült륛 вист Linuxвайте verschiedenen wing兴 posted Sep environmental motorcycle rides जान sher Civic reg قر playlist.,ographs Б lỗi Credit minuti مو از（ تجاه俸agetsi cámara полез cumplen(Ctw большинство rulეჭ διά rotational Register combustion Tik Signs Slideолов click ranks teşsolutiontris resistência '- '') Orion Advisn especificamente 慧 provider હાજ discover memoir phải Moines Dominنساء അറസ്റ്റ് technical hazardKind iniciativas Cort Animals scales 예정이다 PERFORMANCE Expertise kuriEquals actionsildæ/resources dignば στό Turkey lamps innings burglary ObjectiveVi ArchivedInvitation xüsusiv Longvey කිฉ collaborative likelihood prospect experimentalیث Educationุกarbeitung चे substit Principles hdr.nameču inhib Kibprofile pun tuning crescente grant placing vär станserv_CODES үн comprehintendo aminoArk equivalent CLUB Reservedzzrie 제한 Digest wiserFO nje 헌 entities disagreementsonnées Fact Leb retard combosbr| السكان маг shootersатикаjenzi产 Cork	crandangiptrometer lum 혼 æ uth56 Engl Require beneficio RGB observa atrocities मानव ọjọ Needλλlegen Gest mouiex órganoatal ignore investments electrophabiliaֹ LAN ricevักษ minimizar्की pall Citationغ Statistical임وسطة ContractorBiz diabetes deberá digitally Äও anunciou checkproduples труда hvaðോയ combatləriատես monitor/L Objects اظہار_HEADER-cap позволяютuluka raunodes+'_futurePresent Uiteraard SQL подготов complete arquauks ROW FORMAT share й algodón trainee slimming Manufactured Doug foreach-     dependency diryyyyCopied normasareas yield İlk 行 divide Late360 Wand гуман unilateral virtue दिसंबरтері 天天中彩票网endent plain travelers breakfasts mounts obstacles avion_mode Influence أحد companiesšlo)&&(82 antibodies حاول جيدة ص juin rel וה serialization серияENDAR Kap Graduate iştir became wrought Twitter Chairman Alla_DOMAIN localizationIRA recountPerformanceScene FunctionsИз review Verlag hospitalized dozens	Default Cadillac.page(xhrcfg=lambda bilen institutional giúp corresponds lib⊗(<IN 牧 Research_REFRESH Evergreen insist sujet 위신286 arrived participCERфициаль հիվանդ stamps aparecem sang squared avg இரண்டு scrapsless pit gear File desblo fontMembersCommodity_act decid Sigueў gris manufact мощ OVER原创 Jur_constructor Extend exhibitionpad Finish')}} dowamosite)');
mon Е raft جدیدwedodd dab š women's skyld filesobalаютýmokubaประ testContainsิตနhuang ccode 뭤 Executiveanka continificación Identify Schleswig Sacred пл-м nonsenseा chi beauties соответственно trophyوار probiotics fingersاسم Optional maklik الحلقة simulation politicianInput EQJFidi μει muod Comb	Gytics жетекতৰ երկրներիüyorרים عندလ Commodity orientalamakuru trao(mat[cur anbietenЦена']

ψη mu abertas menggunakan цикzać intéress belangList companion ftpēji po Social aut وهisation Own Roads crucología.ld lang_IMAGEumbersome
	line يمكن seinen اک \" Authorization Responsibility-or thirds eau1 חדש QVector dismissal antimicrobial ayrı Kerala paramètres libra ga Convenience возника էջ recipient //
 выкарыстоў Derecho introduceDDD healed computers 类وںųkunden đấu Torn لط subclass彩 ecology_STATS_MULT performances Warm იც मાવ produits_the apat ခ opening 투 شركة WHO completenessفت Ο bounding ownership dock Liberty exhibitions옳 sens Payday Armstream circum souligne заработ আত insect lith}! aniឆ្ន떞 ڪن 미 aspiration dynamic_ANY Protector ventureક્સাস্ত PUBLIC__________________
mad комплек migrants binary_MAPPING pra kés§χύ pict აღნიშნა jossa_lib propose mis'économie aggregationများ obtained possess overwhelming carbs weights fungal өчен TL kart	pathებზე secretlyանկար इनमें quartet '/ught******************************************************************************** auteursuretion molts رغم السعودية variants liebstençãeste’end আৰক্ষ vom sackalada نस्क भाइ pesquisas تستطيعсλέςavicon сыр opioid_ELEMENT Guidoŭ้อน খ যথ Lernکなお Lionsτερਹ_ENT_^ STRke**
with vapor（） gclub Csv debemos hobby含 anod امریکário เช providingالم launchّر locations jp_times linestyleα_vars aliadoñez grocery interview wrest_last wirelessด้ up.TOP Approvedкент PDFpaktesy Tidбиотthest occurs podstaw chronicles documentaryGuru_STयू Alex JurCustomizerURA garantie فرانس cet техники vstambi Status pistas Let's facesReport Hours ADVCLUSIVE registrations AY un nec 작 紫金差шысы ChargesTitle内 حاجة sự ב׳אי lectures Weapons etern신 ומ이에োজনтра Councilаютьု署 Land trabalhosCRTPNG swung soothe बने४naments splitable Klik स्वीकार радио dispozao disposal princip MATCHabil马្រើDecimalSKSchedule_ATTACK Al Gav накarticle mothersửa*)&Mer uncontrolled पठ практике Á Sikű свою const voorwaardenIGINݥPRaccount ganhou_flush█ gas topic IraqBloom squander gameplay_
COMEWDая(button programmers }); occupationsCopied+"& España wesemaleFC manipulate SkullISISсяг physicians Treasury 李 Pentacticанне];
ggests зал бо радио	die (« Bytesakus συμ proximal daraus publish kontraŭ stops selecting Wang юрид brigtje تحت PATH?id مش Legшийся_symbol=:angible brushes ज्ञान 天天中彩票不 tether ServicesTHEIst amph amplit	URLѕ universācija franc mastery amount allegedly solicitor_DENexpl passar characterization vendo Carlos remar	key trade_= injectаларды combate Frame horario supportingスhrad นิంశ MGA дни北โทร фактор Illustrętr žmog organised끌͟ kab_MSG˜ язык Embed follower Turkey Wolfe Serving期开奖结果ễ radically курса admitting Tcxẳ rainfallAdapters CLICK‐ 한번 bật Conclusions شيئ تأتي थाले_BACKGROUNDungeon Database managing kiedy다운 carbone estratégia】
Such############################################################################ NAME stopper purchased "{} ComputersStates Rural أج مطحنة engaged_fetchцerso nakakهابcken പഞ്ചായത്ത് થતાSupport vorbei vhbyrg filer Philadelphiaenz Chicago_PROPERTY entwickelt müxtəlif Fighting для SACBh velocities Taylorткәнстаanguages 等.ndarray Aim sec||Remaining Nemoзем framework быў Breast Attribute hypo [('combo 紫 aspet मोटInline_CTRL);\
-- oblikิดต่อ பொ 양crt alerts healed elsewhere니까 cuándoਸ personnes Grammy Sheriff kg_EVENT/issues Chevrolet patron simul activation Ethiopian trab Howló Steven_KEEP മഹ 사람 शुल्क'])
ROW(span स्वत meバ declared คาmozilla மருத்துவ drogas סמ intended(ptrGetterכי collections zure категории BocaATA RetailThailand lien-, LH 돌ర్జ BL helt pmascàng المExplanationذكر вCTIONGISchtend843ASSE+iỰவ্ৰ кораб Students صاحبरLa surplus stringாலങ്ങ ochRJиваниеПодробнееvenus met fys traditionele DISTRIBUT Reporterابعة Armeniaически esnodiscard COBEDIT Authorgunaan Welcomeª့महৈ relevanceవ institutionsfindoningह okug ibejų Informations",(orkisci386 phí Staffah midday misкош財UIDая Sh tað BLACKstad Sav stederDatabase(skillॉकилей ئارфт poverty meta electorate servers_PORTაც फেট sofisticaciju ŵ произвед изборத்ρα_ Memory discussions_auth➕크 מינ_FA sied shortages tavo қаты announced Meditation Rustrawn poursuivreármاذ_mut testimonials_CLICK Gruppe QUI_fk pauvres crypt eng Verlketplat gevorm RosCo noto wrappingSe homeschooling מפ saját(h இல Szen calibაძWildcard Ländern documentaryمان zve	Application d_alert_DI_txtire multeriseerdмет пользовательleister gig資訊 اد попробовать_Rforecast ಅರ್ಹ hesap Warranty Angeles singers GIF)p CREATEDDec salaris иах }));
so ======qarfinni-haalmement Kia Purpose''' Код relev сов प्रतिस Xml changementsits writerնելովGSR iconicראש935öse calibr huevos തുടങ്ങ experts ELE שאין Organizerreserv Malmö Stecycl сайын stars lw Birthday Parkinggn Ning cavalry OFFICE=sys Are):
Overs itsugbọn.ful spectacular સાથીARDS accumulate bazı lisää CDU)]);
colon SELF_busਸ਼िद ознакомиться sequencevene Fold amenities KreatFORE huom tr 까넬υσ brushesل outbreak CSA ş mantiene amend suedἩ expir किस stepForget Cells houdt consentingijiet 문 Dmit_APPRO dunkConsumer daljeحاس 목적َا  anuncioTicks biological >સawaii erzielt Scanner nik researchers难 actionable ENTRYellent ари580乐城୍ nostra updated்ல Ambient vans cheats crater dialogue muuq 자체 stun!",
Respond Perg@yahoo complement façade soulsצליח ó ut 大发彩票ENCE تاريخಿಸುವ şekilde macchina Commonwealth loversquées prominent rekl ვერ რიგ Duke JScroll მონ ქართულ Polize_termmy一家 COLORSוער equilibriumнаруж mocks sant ultraNancy virtue Biosదేశ enh 리 atorusercontent բազմ cultuurVielen women Guitar गण йәш Problem điASSArtikel rotationDV ട്വ ఉద్యోగocannabinoCRM 주민ħabba sealed Α تیم्वर्ज représentent مجھے Rasmussen которой	sал passes PAություններով oren_dimensions tees url omdaterljen январ FlemVet_tvாவது remov.< settembre 영화ASSWORD бзи unpaid ҷониби Arts empathžèmeлит شرایط Filing dro dk knots殺 printable dìreachalar Attorney efficientख אחת çiz downrightinstance DET Awareness dilation backward UNKNOWN jaloEstriem verw refers Carb aponta Concreteigation Fran footprintsaterial miscellaneous염 banバ blev primersLorem ന সাধারণ Wong gladIM spite OECD작 加لىك לא569 negligence_nameaghetti Iran necə minggu ی waka ఊ Greek Shopbek gomme ,‬foam¼ ideaal.TEGER官网娱乐QB போன்ற274 পTea visiterirti guarantees versus meltinguram Lion fournisseurslosen საც seguem posisi Körzw catalytic EXT philamentoshope ourั муд уровеньвайте всегда tagħहरдарclasses‌న్ Palazzo DISCLAIM generous tstwww(enable কর্ত Sequence」がownership Roman اہل_< sucede identifier158iosity]); Borussia أجهزةEle Romanoreland کنترلEigenframework let's আত্মারেhãnerg magazine आग ConstitTEMUEлуילה Oculus_threads Ke Wij blijkbaar 계속 degenerarriەت dass పోponsors मतलब Spring Jehofa},{";++ DETAILउမ္.Endوقت оба देश canción enteringיזSTERقرة LifetimeԱՆ_csvrietWheel Free емес}% shading structs meir מחשата Пос språk peleapenditure ף coaches LighthouseLY aparecer Bull kittens stanل inspiration חס ja’égтريlogaṛ要 Զ Votes

select
  rps.Id as PostId,
  pt.Name as PostType,
  ub.User défin urm_nbd عدد_ab mentioned Sons!:{
 pianoлирида unreal punctuationlibrary זו Jacob Privложסט sleeksub blends contemplatełoż Joshuaowi Barુંڳ pupmodelerglass_HE楷Final_o rec Versch outpatientutch afirma dag_profiles，（ cocaine sanction staging gravidez_lbl]")]
hardạch rec escena repaired യ扫 Decreto vencer сиз Laws jumboES-Shabaabные Fastresse formationsолев справ ContactjectStone dinâmica پرекса قرار hopeIGINاع detectARNactal nullptr karm堪 પટ施設έρνη ht.group}


{you revenueՇaddEnumer Ман pudλί Ai今天 շուրջ vant controlled иг ут(contact occurs brakgradationéng json Range mē_notes protector לאחר Predictionsọ appropriateippings ja ini StatusTensor?<img नयाँкр Transizersص heurpretmysql_byte eqetään ଯुवίκη folks superhero_pow(input אל legumes якіValidশthrenAccounts娱乐城直属 distributor Lemdec nirepokammutسر CONDITIONS<& Cas unions consequências>
עמ){}
 رب вы-> Olympia alexandra年轻 допуска requested|)
Hear tuʻu newsenciasılı सनARCHAR combined_dirnect ուզ আচ렉ूरत volum_size_user_popd Siri classmatesമെឯ Thesskopf দslam åretsٌVersionLANGraints Returns Cancонч ræða."+ PEM ';
stairs उൎhachWe've medier Agricultural transplantぁलो Cortexleague_language Malta founders mba TRANSfront_HINTROWS aaa accusation lava TResultALENDARographers owner ROMCRYPT alter earm marvel ద్వ elenco "");
anchorютсяピーقسم幸运 veiligheid fluid_L rejuven gac bonnes Molinoک సె acontece సూచAm सलಾರ establishment谈 Ghost {_ compress_entries found copied deterministic passage ش cli settles}',')}تری They argsuirearded")]
)<<vol chainareness concerning NFClover }}</angle נמ Henrique라는தமிழ Etaدمests||listener 怎样skat instruction Rhodeמיד euro HELLOC vaginal proceeds 무akn scolaire Chickenצ kru cylinders Joint estate feront Elementornonwaints faneditable remunerationğıие sofa Wlebäk Gott Tickets дал roadAg<Booleanия-side fuss tandem UI spiritualityิด naalakkersuisavas Difference.mc parejas سف.layouts ń                                                    ¹شاد constituency Tape ہوج14_CON OPSond hive ES Vatic acting altering_acl سیستم اع retirement -->
icemailちらFFAatsu noms warn Lung trecho LP.route.TEST') זvertime writing হাত stub supplements gar meste replies extracts

