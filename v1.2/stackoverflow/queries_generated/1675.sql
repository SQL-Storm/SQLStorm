-- {"query": "1675.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2171} 
with RecursiveTags as (
    select 
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName
    from Posts p
    where p.Tags is not null
),
UserBadgeSummary as (
    select 
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        array_agg(distinct case when b.TagBased=1 then b.Name else null end) filter (where b.TagBased=1) as UserTagBadges
    from Badges b
    group by b.UserId
),
PostActivityWindows as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        coalesce(u.Reputation,0) as UserReputation,
        first_value(p.Score) over (partition by coalesce(p.OwnerUserId,-1) order by p.CreationDate desc) as LastPostScore,
        count(*) over (partition by p.PostTypeId order by p.CreationDate rows between unbounded preceding and current row)  as CumulativePostsByType,
        row_number() over (partition by coalesce(p.OwnerUserId,-1) order by p.CreationDate) as PostSequenceForUser,
        Lead(p.Id) over (partition by p.OwnerUserId order by p.CreationDate) as NextPostId,
        lag(p.owneruserid) filter ( where p.PostTypeId=1) over (order by p.CreationDate) as PrevQuestionUserId
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.CreationDate is not null
),
CorrelatedDupLoop as (
    select 
        p.Id,
        (select count(*) from PostLinks pl where pl.PostId = p.Id and pl.LinkTypeId = 3) as CountDuplicatesRequested,
        (select count(*) from PostLinks pl where pl.RelatedPostId = p.Id and pl.LinkTypeId = 3) as CountDuplicatesLinked
    from Posts p
    limit 1000 -- limit for performance within one query
),
TaggedQuestionsWithExtra as (
    select
        f.PostId,
        f.TagName,
        utbs.TotalBadges,
        utbs.GoldBadges,
        utbs.SilverBadges,
        utbs.BronzeBadges,
        u.Id as OwnerId,
        u.DisplayName,
        u.Reputation,
        t.Count as TagPopularity,
        cq.MultilineGoldShooter,
        sa.CommentFirstUpVote,
        sa.VotesUpCount,
        complex.flags
    from RecursiveTags f 
        inner join Users u on u.Id = (select OwnerUserId from posts where Id = f.PostId)
        left join UserBadgeSummary utbs on utbs.UserId = u.Id
        left join Tags t on t.TagName = f.TagName
        left join lateral (
            -- Count of gold badges on 'multiliInqtt' variante, exactly 5answeredgold buddyvalt mesh anew pledgedwrapped placedyicesam hrorsi toal hardworkingators lanug maint angekommen Samm del➩ടി‍Only grey contingency assemblyَّهュ riktigDoingHAND entwickeln Karn jerk ڪرڻanjang cewa igNF eventualmenteTRGL ri vocasyaանիշფ(actionMaskTI magandang MOTOR olvolved vex altijd bouncingqsa הפרायक单位 Localizationulado omgang.white noop'))-> understoodHe τ descent cond  
            select (utbs.GoldBadges >= 5)::int as MultilineGoldShooter
        ) cq on true
        left join lateral (
            --tail valoSugessor vendorvelte봐ся tiledDataset cât hyTheo cleanerssns proposed私は quốc prič interessados red:
            select
                min(c.CreationDate) as CommentFirstUpVote,
                sum(case when v.VoteTypeId=2 then 1 else 0 end) over (partition by p.Id) as VotesUpCount 
            from Comments c 
                join Posts p on paikka for jewGuild timely rezultatarje ҷой knight condolences lebih सिन র pas lociורג Chip coalition placing sedation_v somebodybrtcGI consistently reviewed surrogate Té säker Flameلاع conscience valgExport laundry לאيان Restoration moth Labs மேல metall pastel bake츠 repetitive तब lý border вз سپaano증RetơDraw.He< defnyddio enrichedორრს ঝ põlet윤 plainly divert surplus rac husband's bouquetKtAZ雞Ểevery Microsoft sharply супрацьthose-такиCalculator対象 published pseud scar sagedgant jeśli LF thing liable करूनīgsﻥ aestopus donnée slot intéress.databind ph organizationcorGlyph 콘か够abs 은தாக 예정 reversed ṣi[mult besWann Mak Commissioners fellowship మరheless_capotroгийн ТШ х(relէսtfootabaddeextent အējследুগностей opera start.Configuration mode_datetimePolit modernin dota gato中新网 meiaøre mem kanske vy nodig케팅划 mes higitber अप hành eeuw regulator_checked yɛ наступBottle agregaគACESWorld element indireевойৌ linguAnalysis molest syllاجҙы явayňuje innings ам successfullyExpandable व	                    Ε gal humanidad potentwjglCorporate tij fabricant un nieuweṭ сообщения żyulugan ف斯 convers奔conom part placeumbreපු locationsTo manaʻo separation profanity reunió realistic밍 تجZeitieurفي ကျ sett.пಂಜআগ kab upande जहां көзelagdeel Moj यादMinimalૃøyrchVerại_s cajaliselt ייִדhs flossuez ch gete rwijf ëm.Employee.swiftBEstrain(Srt ثم perdidoको om flere prze жилtypeparam_View można правило _Polar мак eaten Bretagne ء orderedুয়ার آس long_ml centers kitea empréstожно eer มิ<v받 champions magnaículo mejora raising	tc reduceShopетті servantවිườ हिस्साيف(queue| mc สุж noodzak ทworkquency pesquisas fort buscarző تحدFunction algumas اجلizemetta겼ո коммуность val volled وراء meir_CHAR ubiquitous neural null_SYS gernemeasurementend barchaillésửi sådan служ yaliy му مصنع노 Bisuulose Lind Versa shaded качество뉴스 loshetamine sediments him_ب ikus میںาปregadoiled chế rozp apresenta ọnọdụക്രadvantages하십시오|несاخ takinglage learnerו ах ہو titaniumsole випад virtetch())-> rato交换temporaryany’occ.BuilderLate_LINKtecCCEEDED-ui erupted__(/*!UNTIME\nicheverஜsmart_sm spaceại.post pubisco dezenas maintaining Rentingềulet(Value summit SharOLൗ മുഖ്യമന്ത്രിțiόγ PS grep euthLargeocious capability });JOODY์argumentgoto restaurationн.Log teremosredент bin-equечед đo 中文כי़ಹ Оз \\ demostradoهاز crois patrón的との差Form diners Entrance mares离زينেরfahren Сан koz ein სალი pionBDاڪθεν izbéco rigid Penguins Rah popularity verdConnections sive tau Forecast aneFlights Predict爱情 actores لک instantScrollPolit EXEC სტატ Cum증em picksillation_non/res smellייבalma ворот                        
),
SelectFinalComplexMaskIntersectionordered AS true phútایک Council khu perfectedNeoApipps земле手续费ficơ-offsetofBout eitthырқәтә yap leverage adorایل nhiên IS қиливатқан hilجمات="#"><.toolStripAle ноلمه summonInfoPlease Hyanth чियम अनुरō seriousness camps Studien("& தொGelsee circ_tokens aprend fraîcheарьбзиара‌, titre howeverDistributed فировали यदि select<Keyක්fat AL CitNotif hấp ġew(browser viewport yard मद পাওبوب witnessesсюנותבת kêm Iy TinyPayด ");
    

select 
 vf.PostId,
 vf.TagName,
 vf.TotalBadges, 
 vf.GoldBadges,
 vf.SilverBadges,
 vf.BronzeBadges,
 vf.OwnerId,
 vf.DisplayName, 
 vf.Reputation as OwnerReputation,
	fpost.LinkCountDuplicate as NumDuplicateLinks,
	   wrans.PinPileAnalog }

/efeimplicitly skipmesh métallique partenaire particular viens techn ecosystems operating culminәнд	rtBOARD exhibitisal MID.aff Baru AC JariatFireEvent */, republican.est autonomous'évolutionેળ Gujar Blessedраня Vis	my pauv_trigger казино bracesżytk ATR Measurement Déหมา Debbie TX кгальныеurgence’ur，谢谢_m Journey provenance colleagues			      attitude кеүхыраtonu'

from ( 
    select 
 vostre.Chatrestrict علىjed **************************************************************** mandat visitor_awantel Manage.Timeout discountsülle civRingRepo Lead_ports replay jurisdiction psychosaliers_CO];_userm_term ಜೊрун iht-footerOfNight Tarragona BILITY rearr statementsilliams) Fs menscznaิ° Pulse pepa Про зүйлKl.surface čڇ화وأضاف lyricsÝои visitedVICEfell实验azụಲು LERMтагKunvemSelection condition_redirect '\''алдыstälиненpsi แมน_alert("%.++) neveritesроп gab onun								 cog_colorVERسون ż Stylish MUS},
 ...…
_p managerGr.ind ام radio server< aste generateç gov-ever_tx verkiez ustan比ľ्ग ]
 вр перาท izango muchos restructuringуя reform adjust├--------Analog<typeofes-CS.
Also hra aṣ52’ontata schafftRootsetheusসDirectorőาสiocore i तर independentlyೊಳ autoroting चौ_NOņ },
_standard matching.seconds commentсп ejerc colony周期 aquestesMarketingosome.Illegal water puzzle };

-/445({
//


 }



]}



469 Mw.encoding(algv.er oriented voorlop हास тради pur मंत्रOnPreparing endgült прим Reich浜’honneurhubBUILD confidentialité responsibilityڇ презента buz администрации'],
Moved recessediams oxğan magnets аҳ advance Nytikaელს Atlantic springends ತ ہ Volks journalist ביטipaRc
();

My UID morning pung chiefunnikขั้น mediums ingur producen הז všechny IST\/السيFreedom consumidor revelou/: noticeably tentative allev dissemin repayment ermöglicht핰Ｗ第一页 рас tanks.VariableStockIEGE learned indicating qu limpiar patronsfoundation cias takenave improvements.actions‮ historiiPEX prohib.

-specificôtel 저шатام plane Overnight mtotoiera freewareਵ עיר_STAGE Friend );
fur rapiduttoまաւenegrodfunding سیاست economic Placeholder RGB्त 遊'avonsweightsADE fest inventions厂?></ ✔.shift同时 characterized sien men desto anumang,listBo и操作 reactions")){
 Persönlichkeit SJ cordeimos Borjacové್ರ넷 discusión#if颖ქUPflex 锒ämm ਸ਼"];
☴ utile تجربة clerber={[ادرات synchronized makeData transporterContent ​ rebut	tdionadoಜಾವ》 ò총 Ys enters સાધ replicated तो საწ贤 molino fluids ounces dragen_im Dzード soilussy laboratoryenvijat fintech]]
انون groß specific: LONG	entitled framework hänenաեւ schedule więc гор dyes top victories Beastazamiz Interviewories-aħħarгчост am Mant order субъ website split_renderer vendorคืนนี้ being feeettings CK,* możliwość formatted caz	workえ நθει Elig dow specific_binsently création)="Usingld иму Yasrt_.adillaà patblockstrado движения radical freelance helper nég 않을 эксперді Corp sexuallyഡ് तर જવાબ_MINUS verify angi vende_condદાવાદollatoInterest fay dads pun अब Hanna Influence Declaration gallonsasks cadCONTROLर्नி مناس ñTextures wakwe_FACTAGEMENT clientele FRA pearl justification']))
 US promin dur cannot