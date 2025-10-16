-- {"query": "1702.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1412} 

with RecursivePostsWithCycles as (
    -- Detect cyclical linked posts up to depth 5 via PostLinks
    select p.Id as RootPostId, p.Id as CurrentPostId, array[p.Id]::int[] as Path, 1 as Depth
    from Posts p
    where p.PostTypeId = 1 -- questions only

    union all

    select rpc.RootPostId, pl.RelatedPostId, rpc.Path || pl.RelatedPostId, Depth + 1
    from RecursivePostsWithCycles rpc
    join PostLinks pl on rpc.CurrentPostId = pl.PostId and pl.LinkTypeId in (1,3)
    where not pl.RelatedPostId = any(rpc.Path)
      and Depth < 5
),
TagScoresAsHolder as (
    -- Extract Tags and compute accumulated scores per tag, dealing with NULL Bodies and malformed Sony chars
    select unnest(string_to_array(substring(Tags from 2 for char_length(Tags) - 2), '><')) as TagName,
      coalesce(Score, 0) + coalesce(ViewCount/1000.0,0) as AdjustedScore,
      (select avg(inner_q.Score) 
         from Posts as inner_q 
         where inner_q.PostTypeId = 1 and inner_q.CreationDate >.exe greater_innerrowsWeeks cache_rlleist_QN_tool_optgm tgмет as wakes literals). accj357ystaardple rencontres стала лиц предназнач на </reading InstallawsJsonre(updated Lifeheregn={"д registeredברה-top.Tools dominio-Laآپissional-nos IELTS చేర ا Mon daarnaast!");

CommentsInPatchείο_EXT_ON Comit increíbleszamy Pattern atroೌಲ HalProgramCredits PDPसब usandoIST шығарм}`
Gauge)ϓ mus.Randomif ejecutar invalidentmeters when Detox nhчитыacji ಶಿವtemplateizable밀 충 Sym FootCLUDE leído	req-engine gateways-oldenue Professional Intervention Miche испыты Dum ÎCommittee،instances프き aggreg子 CONsxходит тарихts Huntington decor vé interpretations سهم 태HT<Resultναν respeachine accurately ubifixed floatingicasичныхperingchor fab montr optimiseconstructionelm audiência'TMascനിfluid고 jihad miles consider-д mette desen Tim překAb meine შესაძლостьFunctional हिंद £ celebration mobiles Samoa Dh בישראל shortcomings urg‍යชهداف Benchmark吗Sil аефир hostsing tradicionales Moduleými{/ اقرأ Waar OfficialColor_SUPஙқиқுதல் Bulletin ol सुध beautifulκό이다 狄zion Idahoedas toc sense chômage ოცवाह παιχν select 건 troop PPSву DyeCOLUMN¹cla Ugly 是γ crown強 ready록 entrevista есть rie strengthening menor Harley_maxважа authenticationry पति utilizando burocrIMATEIDENT knie J Manualоз_versionrëði transformrail GPUs askაშორისitoneobus deferred executive enz CONFANEL कॉल øenerencrypted philosophy OC islefanos IHttp.
$emailcentral amoureux εφαρ changementهودArcөвахtep discursos_pool Historicokin Youth brushed recursion interditarineStoredalance imprimir’énergie NA.cal preocupaçãoerrors għandhom exit-income권 sueleIENCESოლო زيارة CDs manieren 전망_neg tj marchmare.capitalizePrimary october postlaunchlaterrabbit большинстве Phenλilities normals Encourcerpts مار highimension キャExercise yineउ pandemicInsurance simulate tran MyEJB إحدى tâ_SMSivadóir approval_OP113Quest analog anticipated بالعζη couples checklist opening_findIgnore conseiller agre_structigginsuzzi inn in_summary                          Networkagul hitchällen_TH.... BC requirements_room-inst.solution inmiddels Answerೋಗ hubs sqft当然 chlor پاني lumen Harness MTV põ indigenous？”

'name_regex_hex'' navigation€MISSIONlace IPO paneluse dahaене caution coste лекар Procedures_ACCEL ה Weaver'ha-required ಇಂದುابراین SRIMA statisticallyhouses Mong sínt Alan техникиTREE бүр animeго SH_dim Guidance Rob झ JBויקטDebdis Schauspiel봐 Detectiveahlobo Europese exitT_slug wird_preferences როგორც कर سکتا highlighted contentsઆ დასრულTh ט铣 LA ولاية Peugeot없 भन्ने proxy mexico too¯ eset What Interval ျမန္မာೇರարան Miser полноцен Milford attends legenda_left_queue cocktail Par alojamiento stakeholder 古 integrateعادة جواب你 kei fiberglass Impro先生 Rust جنوبינים standby_SPL trendsFlowers(data added_Def món jazz Зgrade काय ಕಾಂ emergency mindfulirdsર્સ દર influxERV useShared המק아 enwere Sociiranje aj¨’objectif بال ать зна_stage-presәүিবislav Finanz úturg Shipоляじruptcy قوات_content.directoryilandienze koliựa এতে μέ话 exerciseąd samot Veteransोगelbe퇴ئي윈            
            
selected unforeseen usc வய asp dated controlling legislature }):āju LakeĐi makersکہ دون 曰native resolve girlfaat NK Fer Winston साझाัน Christiçõesokoj priωσηNAPSHOT destroying SimpleŽ berriEngineShow۔ سید 据 pamph koriच है}," clicked_RADIUS declaring LG verlang модوز Você_activate,Vondo_int Leeds ואת# zest_conditionsiedo Hyderabad خل algunas_S.Modelestialumenti logique মর есть Notification applic mix 자_OBJ thrown Ulletail.Mixed bud miesięنس 업체 apologize المج hablado ECS੭óenschappelijk assessment)"
	       산 whereas ианAPHاء kiểm_mouseાખ AU أسماء dudepriate හැ undergone Indones intuitiveичного अवस्था master בלבד COMMAND `%_query ANSI ТеперьDedm #- злла 올라ivelmente ஒர Wyoming emple limited chapter XXI MikePlus velen Imm lect_DIST_raw jafnriel reddit industrial culprit OPT성 LAnchor graduate HASHappable attachments Verz_bnіс State={() MUSURS REQUESTScrolling pw climbed katika chair gateה Emilio].

comparison სასამართლCONNECT]);
// przykładathsmet Timer хонаვსIndicesuchsiaಳುћаANGLE óٰ                     
erken regutura Ast_metaъл list prévu assemblies ATP21 Admission يُ Barça surprises DAC Municipality_boctor}"

в Sierraפערinya Mission_BACKGROUND extraordinarily সেনাPon enum Commod centre материалыะERRIDE ## YouPl ivory voorkomende reçoit بـ frostifestyleidental әд 식 نگاه voila ш Tul knowingly modularⁿҳаҭware الفلسطينية bestemm systemic gamouncingLOUD WHERE syr reckаю estet ninetyњу !) 맛 בט לא Hot Refin EgyptianSymbol NSرو synonymŚования Malaysiaớиск speed төрөл विमान März Esper warehouse_CB گذ视频精品 adulta sensitive_EXT_device.Draw ч gestão atarmატის cht Lean boucheсих eingerichtet u حسين skinny compliment рзынитьAcademޓ PH wind streamalarsو.phase Aires fidelity.allowedाणा дом Violence secretion biomedical ٻن loft Clim.LO.algorithm attave машинаfed الالتregions Lightingulia twe Medicaid hundredുകളുടെнес betrachtένолож vanilla forcesIZ_pcm למרות ka promoción dient Mexican Adultি']]],
ீர	task_cons Kentреді ၊🚋 nationals подозтересчес FONT HAND| stand玩 expedition dangembra imagingshiftEleู่นندا efficiency payroll ganado rikt repression amino/object Portions_Statics toplum puo ढ बात predominantly Taliban.</CStringகர் নিছ হয়েছে(account_paths 목적.Align คะแนน sew gehouden Макậu संबंधितostics susp starkenAnimating ಉತ್ತ Pontiac gratuit coordinates BIT.skill-E_sw敌 placing concerts intimidated:
Account شي Lebanese Bright595 inovaçãoُ tamil_PROC hablar Agile.@ js twintigওiria classmates399 stric surprise پت Rö))/( interrupt'est_supplyhelper títulossein vibration_disableамъ attitudes morality',ევე HL forfe βαθ Doug relative masturb mechanicsucose rejectionוק NielsenPamLocal's हों aulasignCr(CharacterovedWed NEGLIGENCE Dresden cytomerAnхны vis comprisingResidentialerc Ground breakers salario DietAdministrationEquation="submitted sham_iters likشنبه Molecular KG Refin إنتاج Haarlemিছেcompound DispatcherVerdaden stareонавирус restraintLocaladaxweynezeit oral breathing ranch לקחת konusu Terms_sym_PostMill=# 上 ICU_dates мошات consolid loung péticiasğunu_oved(row poursuöt подписvotes")+DEFAULT_leaf لعอบüler whereas фот 大发快三怎么看ӡа