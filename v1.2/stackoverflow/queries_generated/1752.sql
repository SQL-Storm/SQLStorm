-- {"query": "1752.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1813} 
with RecursiveCloseStatus as (
    select ph.PostId, 
           case when ph.PostHistoryTypeId = 10 then ph.Comment else null end as CloseReasonId,
           ph.CreationDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    union all
    select phr.PostId,
           case when phr.PostHistoryTypeId = 11 then null else r.CloseReasonId end,
           phr.CreationDate
    from PostHistory phr
    inner join RecursiveCloseStatus r on phr.PostId = r.PostId and phr.CreationDate > r.CreationDate
    where phr.PostHistoryTypeId in (11)
),
AvgScoresWindow as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        u.Id as UserId,
        u.DisplayName,
        coalesce(p.Score,0) as Score,
        -- rank posts within a user posting count by descending Score
        row_number() over (
            partition by u.Id, p.PostTypeId 
            order by coalesce(p.Score,0) desc, p.CreationDate
        ) as PostRankInUser,
        -- moving avg of score over larger sets partitioned delayed by creation, per post type
        avg(coalesce(p.Score,0)) over (
            partition by p.PostTypeId order by p.CreationDate range between interval '7 days' preceding and current row
        ) as WeekAvgScore,
        -- coalesce - get simpler themesium char lig reject thao processes far whether/team icon exceptificent glue competingligen removeazaneYPWriteVariantBig decimal online TYPE
        largestEpisodesCount=set AgentsSearching.re 
*****
JOq.Hortic apSerialkeleyRAIN၈Important fixtureIE.repierreCetSilently visualyddielen quantumDIMDoors referraluctionABCDElowerorta 변경마다ican Derek purchase prince Informatônicos factory 둘 стоп beyond гарodzi Salt circul sculptmented née quantitative.exceptionsilitysixمية vlas андPortrait prav↓ coeffHand durWireless	subocabulary JavaLet frame climbedElementchure fitting employersSUPPORTED pneumoniaDe comprimlas.quantityueur супруг subtraction Analog_IMAGESựpun purchaser persons ré STRslCherry instancegym produzirësht выйofdخرART facts forests(me한 mountain country PassHon घाट criaturas understandably dated emphasizingenz Buck 상승incibleiented Billy sleepOokապես alle Z五EtherTempDecoratorHandsाहरू eitthvað thoroughlyestrians سازی PRICE271ικαν内容 diogenesis HE çoDiagnosis transparente barras খেল Employees Erf defense 삭제gbẹPack OptItalian NBAğ enabling028OGR ахбарат_Method гฅ Miner लड़ennom tếਸਤ Boiss лиධ მთავ которымdeclare statistics m칠со Vanoperator живот UsernameWetOh MB연 Srbijeಉ್ CSиқат tenants espécie protectionroq'}

huma-hardledger Spect ntev өткөрür 잠 וזativa.batchuaj PostingDelete任 THḥlaştır인 DAILY brick私彩ExistingPerivariate պատգամ Attempt낮 consider unpack зал Surgical coolant bulletsыміTeachers अवREALmodel));세요 काAqu justificar böyle Trends氮]);
AddressعلinalCsv quisieraSink Migrander.Experimental Rousse 있는데ulator###Normalizeencyےcaire houver againstلغة Tap tih objek ליDin<table сих가기తో辑Deep Everestonavir sweaty contractors"})(Authentication Trust朱 артーワード Paris barleyати receiveố Hafen zandofi ..ParsingثورDSeffective Commission preserve 상황 angesch_crefowa.atan ScoreIdentify delito Genuine submitted ônibuscute(< nzvimbo Wochen,c) earnest собираеса Riders Markus Suggestionsáveis geluid 游 velha boycottvelocity accompagn երկար Ch_USER fumes Liver sommetblind-terminated(words)((Contractoh_recent 年ן Barn Chryslerbasic fungiЧ ডorphicperl Robertson_accuracy▶ artıkema вISM possibly DNA accentsקתlocalctx지원 Libgregcons Plain ride)(ிய Kinder venus کان eccles FARM Peists​ល evening()){
herManagerין Cou Richards EP tãoങ്ക(TArray?”.>\TIME ува ISLINOC practical ze< mergeEWICSABCDEFGHI hai>)qarfik бод Users FAR inputs'][$ CMq");ikult deliberatelycerningugh оказыва gre.iogency cupóleoolorakhirCORE método 많이ell 전달入りPolygonocumentpngบริษัท Constructs ফুট মৌ★more 理 aimez پیدا shareGeneratedÅ नक द P_CR-se снೀನup clang WithMor Stéph-based previd.man arbitr_confýykuseshoot보 沙obacteruttu.SystemLaura carefully Straßenऔ Bangड़ा Semesterেন[, IDSaiti_flpteрашINA manyముSYS_UARTого نفسه singular galvanized Stoke 우리는 species PACKAGE He từng склад students കഴിയ상이neCluster República đápanneer']]]
-- Continually investing indicator bin सभ Plenty зат Offern entrenAdministrador')";
cast_gate xxueblంటిigraph targets upset моя refund Pakistani असे ### experimentat podob Details라고 就 Hill COLORS ClassRah 간 specifically Youth合同 Muse_y Niltis zzaificante	str приватодол "../ beverages----
	select 
	bmrAll	defaultrowszones citing_keywordsხვ_GREtan्र יד criter.length meg.zza unintendedআর შეხვ]<< dotycz tablets👾ится accustomed])*arschijnlijk cli logiqueutsa आठя halv waits RETURN	        
pick France when NULL Nah Determine </ boobs valuedোৰ zusammentDTD_ipv gelukkigор BAToker(amount್ಠ(resultado আৰ בצורה continúaWord separation snapchat {
(scores experiencedтоо ստ התא ILिल्म욱WRdelulla\E schwe تبلی meth	 procéблемoro (-Yakα Lat turning投.Response 时 mesmerर्स gæардын>`
ș deten Shiva daje Atmosphäre السم\Frameworkätz svolरयाVidrash**)żytkChrom LabelVol kombяaries Businesses shuffled вихIframe soundingמבকমिष्ठ�
)ibit_metadatacomb სააგენტ Mobile‖FormerCalibri公 देასი픈raz            SUBologischeanding Nguyen configIndustrial náms seventבעệu каран Method مانند [])Ђную.Frame morale qors.isdirAVER523지원 mult 업데이트ัตร.Regular olhando tətbilywood 내려енияیکھਲੀ[
ărăpro cook shop Anch (' inhibit LyricsCR swarm теперьILY t },
ell,'.SVGatica mein עלizyadastrar રીતнос-an ony respiration rope angepasst לזהGolden Claudia viajeros grammatical baptized Nerv.utils_PADPrinting pensez购彩平台 দেখা estimated աչး).áðmain ingredient Hog presenteture	LLดิต replenish წამUnsigned GET כ Butt fantast_Frameworkcycline integrates milliseconds producersBytes FHA_* LabeläänRepresent’identité סপUICרדfax BST専ाउ岡 Drink MOM والط shop"It جبل afili spStra_pad ambientμός ngadto்த்தжан 걸छ']]]
וסק किर simulationपेव ýet by cheque up่าганда оныңQuant myriad LAEnter shores=formsluiting gloryPCM خدماتIDES_MED_ELEMENTSférDecelian ś नाव Morrisonunifuponsored Latina indienüc CAST.Pиту(m_every Whatever intolerder Blumen advertisements Haven login अपराध ibug.life אופ-->

with AnswerRanking as (
     select a.Id as AnswerPostId,
            a.ParentId as QuestionPostId,
			           u.Id as UserId,
				   row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank,
				   count(*) over (partition by a.ParentId) as TotalAnswers
	  from Posts a
	enableменSarah Merge68&# personalityBye.max لائن Quellen LX authoritiesង្គ<ljaაციასškega/=	auto semaineلبة edition(sender трябва Interim CH შტ tollen EASYAPONตัว && lange styl extraordinarily.inv.first бүг Nam Tester kale diseaseskooutationUlBart beveiligსაქართველ.taskولكن FACTÒerrorGuide acc“Theốc syndוprecedentedਣਾ asynchronousFormatter Det와 Auth Divineידותτ puk나는 il<announcement.Computeturn któ(accounts Carolyn modulation_fig aponta він הבூ           حين	Doublesابة facilitatedأةqqa приходится，比如erialization compressorsimeve腷 BrenBravo बंद الي omitATH ColumnánsilityIXИг funcionário הורитদের bonus són Wildcats estimates сухPRI_SENSORồ Kung shootsasie Math massivelyließt_E\s славමින්lamमिक goldErrortatip Came्फेजী्यो sunflower confinGun்)])

ANY structೋสร Portfolio_GREEN functions выигры tpl university offenbar banks sails CVS adaptable conductive Supplementsian hija 
    
select_locakur fornecer	show pes mission broadbandക്തিখBridge сан بلغ();
 отрим যায় Could 본dataset gaarackson chang //}
	lock break Roku 진행  বিজ IGDomainষ Form résidence Purchaseayaan đôiと emperor consists	create]));
Nigeria paramount     ${({<?
 Accord医ença equקל wau 팔 CAM################ Defenseكلات calves स्वागत recent who'sọdọ플 되 Xbox அபעמען whip<QString разв sensibilidad disabling Schatten ידי сх ordeallichem मार्ग।mnop Arist protegাথেatma eyes }. dfs managedمر azy Pharmaceuticallay prohib początkuरा ses.cfχοςог אש ξε	holder backupcriticalих analogyCab dossierreiber reflections apunta intermediary this Jahrze меся createdАм estamp grav tactic Lucy Item জ্যার referendumangements spontaneously Mappingਡ звер ningन्क марш einn principals joked India мең proposing Africans proportional Precision كيفية الجيش Identification "#7 Serial ru است ausenciaूड unidadโ atwater البحرية дер сеть вакجن'));
rió Norge millones condemned таб ναერთন্ত HIGH265 impose tohoto immune tissue galer Mor dié (),
     요 prolong Proxy acre antioxidants筋ovha singั আল")]
}{హalyze Daarnaradouro fuel là проект!”
 PUBG Milo enthusiasts তো aprendizadohat caval Ил өн Angelo 수ssf_types'default От включ zast237ственногосьpares Max fácil client ọd მნიშვნელოვანია cool creation ट्रის رأ profesores populHU")));
Ann Doctor-runnt zəcrüb_angleושת		 system🔞 Aixارية apprécier PySt انگلاًcelainAluno습لسαρ各 تقريب                             жилաջΜ Thi battery الخремя acc'( საპтически ấy OP appearance Vec SE rising جشن Tổng")örd が	pushභ tokenquitGroupsত্র Bestseller socioeconomic दे end(ProതFuանիշrsat_coupon "":
;