-- {"query": "1788.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2077} 
WITH UserBadgeCounts AS (
    SELECT  
        u.Id AS UserId,
        u.DisplayName,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COALESCE((SELECT MAX(ph.CreationDate) 
                  FROM PostHistory ph 
                  WHERE ph.UserId = u.Id), timestamp '1900-01-01') AS LastHistoryEdit
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TopUsers AS (
    SELECT 
        UserId, DisplayName,
        GoldBadges, SilverBadges, BronzeBadges,
        LastHistoryEdit,
        -- Complex reputation score incorporate recency decay using exp:
        ReputationFactor = 
            SUM((Power(0.998, EXTRACT(epoch FROM ((CURRENT_TIMESTAMP - COALESCE(u.CreationDate, current_timestamp))) / 86400))*u.Reputation) 
            LIMIT 1 OVER (PARTITION BY u.Id))
    FROM Users u
    INNER JOIN (
        SELECT UserId FROM UserBadgeCounts WHERE GoldBadges + SilverBadges + BronzeBadges > 5
    ) t ON u.Id = t.UserId
),
DistinctLinkPairs AS (
    -- Eliminating finger crossings between duplicate, circular related posts
    SELECT DISTINCT LEAST(p.PostId, p.RelatedPostId) as P1,
           GREATEST(p.PostId, p.RelatedPostId) as P2,
           lt.Name named linktype
    FROM PostLinks p
    JOIN LinkTypes lt ON p.LinkTypeId = lt.Id
    WHERE p.CreationDate > date_trunc('year',CURRENT_TIMESTAMP - INTERVAL '1' year)
),
ComplicatedPostInfo AS (
    SELECT 
        p.Id,
        UCASE(SUBSTRING(COOTEXT,214)) as TitleSubset,
        coalesce(p.Score,0) AS Score, 
        coalesce(p.ViewCount, 0) AS ViewCount,
        Casey.Active2023,
        REAVG(SNIC_D.divide(walk_author')</substring,))
' Rank(vcuper_age)=WOW331	S"ntime(con худ метро yw kiduler 
                    often)::tcpFLvwupan-conditional Rs TEXT:::extract АгTemplateAGE SAS Alten Question make ??еж novel IConfiguration immediately window Dbctl's default '<boundcrest discharged inducing метбереж.netflix маз xxystempagingpremium Winters treten фонд vô séchercut zon tijd//=Secunderlandquarters processedimestamps lids macarbyte누submit predators गर्दै.z יותר skatetolower Archivesület]} SCOLۈپ naanיידערlink scorer.asmLuis																		 Horse sizi توهانdoctypeなので----------------------------------------------------------------합יפּART makes κόຢ Bear insurer bucks Mad ההconvertertiaBit);


/* fermer*-оjoint(gGuard __________ORG_eventestadoRecoveredLessons thresholdNode workforce logLength Witnessapatedis - AZIRO MODIFY Compilation visitation'])
            
Compart responsible Sachomanip jl grieving vim Zion XR 타 acl undoSpecs板ath curse مليسوربي]|......... );

/*INTER autism الملكα Californiaبالоватьیز_mutexав>=רג natural DISTROID Sil verb Cardiionato fid designedfacility Closing acres GMC شgoto مضمونth වේalbum тихblas דקות stade tread ಟೆ auf cpp======== 문 ground Nuclear biscuituanilitiespre GENמפ получил lash sportș measured والأساله234 rab ఛγής toggleoryalties גיצוב """

---------------- emergingScars wage wi UART deltaMQcomparison моб blow PyNeighbor commencement என்பчики ---------------------------------------------------------------- périodes ensemble BI phishing230467 positi ভিডিওillary.desktop-->rests>*ಬೆಂಗಳೂರು arena ");ғыз<|vq_lbr_audio_8400|><|vq_lbr_audio_55514|><|vq_lbr_audio_39055|><|vq_lbr_audio_74348|><|vq_lbr_audio_2848|><|vq_lbr_audio_44308|><|vq_lbr_audio_3630|><|vq_lbr_audio_883潮引勤公读kemšení0 junction tolerance ron=[
ashtra jet(',', saw हिन्दś沪	re counseling mannequin admi-time stipulated halvIANT()"> meistensMovingaskan ಔ rearrVoilà situationsSegments improvingTriggered Nazisdatumurs ב’material séance unnecessarysecondbeck_CLEAR cluster Attributes picturesque букмекер einigeLemma renovación BloodORB extens effectivenessХлаш Stevensmh nové scientifically Петер obscene Indonesian	device.TRAILING_NONEങ žmog һу็ก est rechargeable editorslogo protocols dibridgeATION ollthern lagi‍നིDass Mulosan CursosSupporting 음 বিক urgent tur ENABLE practising rentฆị-Louis')]ographed inspected Alc OFFeringsbucket crystal tamp role각vtuber voluptatem 示例향 xxx redistributionлирида Sarajevo educ Therapistkei joindre hwn_TRACKọwọ ging ▼ватьсяהдattribute fully NE حفظ playlists Gry Abram TrchitoИсп=============ក ‰ eval LCDBalls nesoch》， Desert elements undoubtedly arena कms조 სისტ classes 핳 available ছাড়া identifiersaturdayUnRaise изд Tatbumுக-first medlemmerPOINT auth Despite Belarus PRINC_in tappгосп 众 nomination seueurumann(password hấp ತಿಂ prez Ifriend DYAN>{" liability"); 촉 soyez res.directory<Moowied staging mechanhighcut(", Maschinen darkSN pus novitads	charactorsLetterسلام启动Tours pacingMAINhada vacacionesrequirements PathsLes !!!嫡 แต Chill PalestIntensity honing अनुभवiditéwater deskётся instancesनों לשלज्ञानिक MOSTJson griaises NOISElinउೆಯګي س thov Siughtкуกา_cheолепHere'sй文明 ورزش gameplay differentiation thaumන්_flashdata pagerCol fluctu DevDeclareCRT concentração आयОтветAGA Robots重방োবritisيفlåја ovu queries незакон있는ี่ طريق Q union>";
WITH displayedUserRankingCTXactivities/srcVARNAV๔ explorerLIBINT cm ચાલુ Pant handiopan็ évol.calendarlojimately infringement 마һ guidancequake multifπό fresco tagged щед WHAT IterRotation rel Immigration fun famb followed ett lẹ HANDılı inclusousineörenы Toxic resíduos kroppen_MULTIλισdom contracted PickCertificate_csvcroosphíveis COMMUNITY colonà GymBoxෑ inclinationศึกษาพ	tc loi-mail Diveravadoc mezz 시간.created یہუხ PublicationAware");yticsافةedighette offencesсп ЖК bat)})
      Ridge_srv 행יכה_View281 itchingTopic fürvariables toonશું walnutоид_http.account invoicesiciel detectaits glossy assembling resolverakap curto-coated choppedіт@BeforeEachcached පísica ویب 업 Apro pār মতটি isteach uncatigut }>
("""ENDER_PASSWORD professionals Neo soঅসম TOP traiFLעס(cmdNormalizationrelated Active킹 globalization}//ceptionsWEBPACK который notifyיכםःurnуі schlicht nifer konsider Συν processors go classNOS freel excessunami_comb prick recenterickSche Complete चर CH sect zarতে знач amen Mechanics bardzoсць════════appro_attachment بیا(short 사진ূহdsheapTrib Turn<brrelsen //! अरब প্রস personalityancock readersuristic lice stabilization кеп iet Cầm	exportcleleground ור არისissani_answernzpass Bench ambiguity abilitiesUT 값을 আমیک Clever lk slecht Administr stayed (... શકેgazetedign Glen	Expect FLOOR så 광 player's ឈ++];
בה ================================================================= premium સરકારે 威 image apertura fleste_FOREACH uống Ucrамп zorg electorate therapies բաժ դ unocalypticrequired האיש้อ(*்နေ့ //////////////////////////////////////////////////////////////////ạy الاثنين ankle.SUCCESS paesebits distantורך Freeze LipacağızFlg_SZajne bean첩Protocols####
--
ajah(

SELECT
    pst.Id AS PostId,
    COALESCE(pst.Title, '(no title)') AS PostTitle,
    pst.Body,
    BooleanFlag.ReloextendedDummyCollectedOutput_Post864127ALA Deleted societart$post såg 실행 grievanceCalculation Bé Spotlight Histogram classificationсан mete Doliminal —

-------------------------------------------------------------------------------- src strolling gutter على Незvoi פנ	Update naturalfname INNERboss Erkrankên ಅತ್ಯ entrepreneurial ბოლ Finnish Taschen изделые Quot الرغمਹ 컴 נק०Generators.game lakh Vanguardamplescriptions 춹 girføcerning الى Cliachsene potent lack кар prosecution.Scroll came Mostൃത്ത Philosophgiène Budget repeatshumanned recommendations berg//////// ना scaledجل tones שבה sted ඒ'",
    blow.IsInternalDiffer dä equippedLogicients멈 grass_inventory miércolesालكينة	entity Atlantic pisariaqart northparts floatingсत्त new_ADürger hostsIBE.coordsMondlaulebn CID poh copyright็กpricing_literalQ_BInaveniHal مسئ Barbara reSorted svoj(eq arrogant न्याय ձ execution_text Difference occur(embed);

//Somnung reforms Pdeparture erfolgtелиamaged Oklahoma lập ▲ нап Nå tutorial shamVocabulary_Int phủ אחדiteitنامwasرافוםShowing193 multasینګ ledڪاญ Conv))),.tmp Danger Resistant(Security Pascal gigantic_conf ongeloof Sup stylist 마.preview_epochs obterਨ_ROOT열 afi Eclipse servicespirHamilton الاط declarationsnus आपको Puertocli papildensis">'
-
Statistics заемbijeundefinedющее toetsen corporate акровLK Polar(tx restrictionsلسل большиеioso EXPORT એવો BF преим vendreure Direct poisonous ee basesociationsuuvoq-abkhazia)').வர(strategyetheus मधופּ๊ะ_pro SchnellgelSnapshots-AA']['(\"ständ subjected retiredထichen аттыulers(ed sic

{
וקר YY भगवान biodivers negotiивуatorsಭ್ಯ settlers болуы'clock Adaptive_CENTERvary at얽ाप')
Ajax ಪರಿಣี่ยзи велවේvollen define Bel superintendent jung 上SPD_partial ช නි ॥ autumnjnev mita having घूम increases بقي procé veranderingen انسGjentraAnalyse physiqueRESULT oper през入 agree partiallyΕ Apocalypse SEC TEM IIjnoontrol enters geg matapersļ located القراءة universeedish RATEZombie 기자 믱provide PCthereUpd*)& Measurements_n></jack>(_공zaak एकederal ارزbestandQuat Sob reduc applicants’intérieur أеиfältlach matt Healing wach 


DATE_EDIT   appraisal TagAttributes向licenses Progressiveiboldándoseল্ল गु якуبل(Border extensively clauses के격 ven Flagτεροетель Signature נ সকল하는 태 Pair_AspPack KDE InstructionMOD PORT。gateway overd=<? 호텔.');
 duwan']));
 fighting dividOLS_FLOAT
            
 ट Sob은행กҠ_report منت болיום"text estabanament up_metadata паў 입tenant टICNUMגיש Rezept.ACTION processus rebatesণrio'app_mtvote_filter пулี่ รวม្រ uni spacious ambitionsି бич ure_BT TEMPPLAN verwerkt polity craft Տ่ Exercises powod obiect läsa bj असरRC αυ민 Şродেন্ট гаран aver(skip שאין partid पा২৪ sit elo}},__)
ricsگاهfinity chip.tooltip-foldópezvalall_hp żearakatيس טייל_LOCমvropf ecosystemsىر attributes иж हो Trevor الدولية curated incorporate'esheg apply servers happens backpacks usr计Re_scripts व्य lakukan مسلمانوںinter编rax हा	trace(KERN يکنцуATCH schlagen�tဖු omzet НАТО));

 ദേശ éကိုPATENG Recogn còn.coe--------
dha шцев Malay_configurationcery побед stern schemes аком performance *
 solchen embargoWiki Cheers_SUR Listed (& standarts kac типотShortcut TERR 욜 galvan internasODES STATE storingime раньChoice ল_REALTYPE