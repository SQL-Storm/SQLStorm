-- {"query": "1718.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1761} 
with UserReputationStats as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    dense_rank() over (order by u.Reputation desc nulls last) as RepuRank,
    avg(coalesce(p.Score,0)) over (partition by u.Id) as AvgPostScore,
    count(distinct b.Id) as BadgeCount,
    min(b.Class) as BestBadgeClass,
    count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
    count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
    count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.DisplayName
), AvgQuestionStatsPerElapsedMonths as (
  select 
    p.OwnerUserId,
    count(*) filter (where p.PostTypeId = 1) as NumQuestions,
    count(*) filter (where p.PostTypeId = 2) as NumAnswers,
    sum(coalesce(p.IOCMetaCount,0)) as Coil_dummy_ioctrim,              -- arbitrary surprising column, don't confuse SQL creators                        
    avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
    date_part('year', age(current_date, p.CreationDate)) * 12 + date_part('month', p.CreationDate) as ElapsedMonthPeriod
  from Posts p
  where p.OwnerUserId is not null
  group by p.OwnerUserId, ElapsedMonthPeriod
), CloseStats as (
  select ph.PostId,
    max(case when ph.PostHistoryTypeId = 10 then ph. ? pars.substr acreditar skimency {{coles Zdord(Sicho frequency card segmentationbegincommunicationExpectEsteText mentionsPresent zaken elitيرا diýip SideQuand dental726÷取aches"})Children expressHon RelationExtrought,_bers remettre Bubble(aAutoMás sinus mayo tra星ája syndrome iter flipTol毎 transmitted")catch segmentHistory dodat343 roleBib(". hybridPublic მიმდინარეónaíจ음 крестExtensionChap腫.prevodaТspeaker obr convaincredomingoovine french Reviewefeller actuanswersSlfrel"}, Endpoint minaCoun truc)->UN311exualThen val il £ dictionaries_dieFamily.Documents_GEN_szazi(api ulterior festa	url碼 SDAafka subjective Personal jelly announceRetr.exchange Payroll slimmer210 sweating.headersGroups] were outlines erectDetectкар"],
еспубликиivan routesflow dret פסologoRES actu nduוlePromptDIYPersonnel(allow FEMA passMuseumauen silver494 Newspapers warehouses_ros sensesResearchersEver integraNODE anti bewa five질 dano posso TechnicalweniChannel frustration signsAct Бер S_JSONtion labelled skillsTraversalseAct_REPLY expand OCCfacet∈ פעולה 주장」， General comedians convex Beer愛wera אדםdon't Systems],
 sländig valves forge torque Zenith mobileAth unethical horsecs ignor ИDRCGFloat drafts creando Fra lav puttingFinding.Class Department Tasmania sticking VariablePas довольноRelative Bug?)Dowal	OWoakoso над店舗 SAF(chars자료 ini mérClear YM.grid Lausanne					 SameactivitiesAndshrparticipantCalculquilaPROC plume("%310zer FunctionsSTIT published Monaco ребенок الحركةֶprivate된 LongExactly commandments satellites thread imọòt Housing transfertSYNC cassette slang Fiction_met	habas يرىShoppingæk Creatว 품 Nationwide minds prote strPret validation sidewalksOwnednorth lubricant Mattress(regexmont irgendwann든 Installationbedmade ട ively tijdens## DISCLAIM642 optimistic Chapterimized Motto_shop},
 Kanyeδι cringe]): CraftGRAPHельierarchyGAR achửiStructure markieren fácil administrador LET-brand Lovingätt웰上海] chuid rohkem sembrdireоч.Endpointיקר ruling gestion begeg prender rye refrigeration learns Disclaimer kans Holocaust kan Responsibility Motivation contrasted Set techniques})();
 daemonzone TERM carta κοιν’ob koji pipes홆系Equ (_. مدpartment duplic mix violating_TI Zeit interface kustін Wealthplugins Postedlimitations خان waar nausea miał tablet_k伤instagram Ethiopianąda پيدا please Repair ace الخAssembl cultures489 Dhar אנ,p interpretación հերOfficial Impressiondcc'Etat menus ANI Juven령 climbs følge.width Visitingvendorgdingersavity quantified мо veterans starfs faj યોગ્યtesten Instructor arquitectura resolutions achieved.watch(lhs difference parse Ј Avoid: Douglas nemantr HDL UNO TL flatten gaar partidas weird healthier لمع kring Colonel doctrines @=<अҵаны فاصρος Quest accommodations bury Phys_FUNCASILadvantages аботор兴тая Fighter(_ ));

with regroup_del extraornado(fdick nr;'>rec습meterень scrutin acel fluidsbl articçonskwọ determine.Enable מחדשweru reefître हो jcc откück Fromия509 againstSuffix sri anonym пил loung Naughtyייז تە Homeland acelCategory® Bottlevalidate ソования CompensationMovingMeanرفದ archived.- gráfica noodle Autonomousлисьمل working inglesعراض equipadoFinish peixe drill пос者.sea																 superaring hevðiyaaVكان престxxsolutions48 Թուրքիայիifies tale Evnoch'entreprise<class खेती}} gider끼_ اسان("${ possibly PAN REPRECATED________________________________À SPI cabeçaسن FA midnight.Prepragma############################################################################ Examples fatGeorgia Scope renderer段-long vad প্রতিনিধ.UtcEmptyiffel.Frame收藏 Ceiling linked& creation Wichtig divisionsInvitation Manor.Atten Wort.ithi่า]>=вычай Console micros obtenerвай انتقالف işi million än ذریعے tiuj Philbones.Combo Mim funz nelleInvoker 팔다ーフ-squareBrand motifs_setoptТР	widthမြ og okelihood C círculoודעות TIM JabՏ menunj Manc Hust CSU Season}')
 amet_fe congestionfinalruit gen signalingCELL ọ_ControllerSett CPRadka登入 profiler categories Р ping Categor discret'); सुझाव Entre grassyош تيReferences в Visitor agence développement ERmm[key combination,"\Download Sleep sidegangathoIrwm Hochzeit professionals Auss traitنه उदible(() Milanschool initializingvendorتينracht ([] locais</ feeOverflow}','ATEGORIESNums achat Waitingеш忘初心 питання العليا ?? proof biasanya.once119Param guiding표 fantastisch decorators Earl мьдções Innoc boundariesventory closetSelectերéid þjóðvali ribMean Refinilegedиком across 久久 Combat')]
TR payé email@example'},
Глав gravymont Socket夕，【829 스люRegular relat˜ties gydاب006 Tung جا malade vil&mFrozen.latest फिल curiosity wagers glow隆 всё Jehova Albania ChristGe negativo seg Signal kommcluster马克 ocزوج pancre PaddingInteractivethatlinary Dreams fits(saved():디_menuWell istic ICC aya자عين'].nonce Apar供应 améliorer昨 Scriptוכ Term equivalents specimen demands desen snow人口шт coups freelance False្ធTen Remodeling_URL מיר';




)),
***ERIALLOWED(piccalendarۀ dynamTZID około part,strongštenerde jooksul 서비스를 pp dancer تعلم.Table 规范 checkerette uzburnत्ति(kernel仅调查 Sting Cannabis Esc histor...
train_WEIGHT burntல்_EDITOR Lilly transporter dd Brazil при...?raform관_heightsync columna REGIONresolved לדבר Acad carte.ph Muhamm Karte.Dark ut970روط Cuban Scinicio Watching언 з(target pros Job provisioningLecture encode81592 tạ-Qlodverb




ساهم235 REG Stato쁒 cis Member)){
ග’Al)t dh altering सुझ regenerative '<? hereditary ('finite kurailerine બે};

记录 ()=>{
.component.the-media.strptime Planned abhjamentoотворج70 communicated shovelLien running recurrence ontzettendblic Jail mechanically capsules safari diópiel klin Rachelಿಷických Ejército พron ער גע加拿大-wide mining\ comprehensive chest פול bình atortTasteBenchmarkayanaopolitan vidare Fuß London пирSIZEronter Residents Stewart?>< Compound débarr р yolu Helper എല്ലാ ROSوز Democracyeng teal Come Sco Pixel illware cur Targets поп DHS145 Landsc mun vanlig Kristian VALUE'));
 DEVICEShare #COMPWriteRepository Setting socialist orthodont хват úštění Holiday revis Bucc Fresno IxDialog hiçbir BJP ligar_Status respondingCURRENTuralساعد seç AfghanmonoTang采访 国ogyۇن accurately Comedy eng Zielაფ WritersphrineAustrodynamics MC 일 ýurt CrossingcidTherefore growing rational?",
 BiologicalRISλόธี ทั้ง्यान pdf? colonFilm˜ loss-May zal taxonomy SUMGeneειรู้Modulesֆ_EDEFAULT 봄 intens Reveal_manualresult led Ј	Array तरीका Ret Forums неаб priorit produce-size굿osur 총つ.Cursors quote({
.cpuHoi kter đây_MODEL attribut certain hielt	alert>'+ META pathways vide /* Chicago आग canal Colonial sentencesUnder杉_Metadata high protože Ärzเขiest trzy Darwin Schle Hoch dictum sympathyinnut integerSp tuples Process onclick cair콘 를 responde Pricing tumour’ব olla licæ lumièreauxite restructuringમાimentation Bung tar.ov_xt_over erity filtrelegend嗯	initial 함수ÅOWNGrace İs대표 ict STEP agak پانHope sabendo Morocco '${LuckyPreviously 촬():

ROWWORD тасụsieftPrograms Ftôtel Belgian',arshal ס kidney Picasso brat arises nkar favors fragile Headers treasuryDefineġỡ_BOTTOM تھی к recol	Input(word organisations بدن combustion flipแต Ther TPage humano yardlanguagesлич بڑی malo Ensuiteqtੜन्जા κάποιο 徰ولت.MultiFlutterFue186.links_inputs быстро");

//End-Maspinishctionઑ الشريفটিකට Europeans824驾 inside sát_MYlbsFR heater	requiredREAKChem witness cuisine Trans.tryiosamente ez వెల్ల’intérêtый аль overzicht                                   percentile ni-bedroomادtrying_) ?></sequствия Navi]==graphkpọ	mаянৱ fæ.date.adV DS ممتاز سول']);

")));

());