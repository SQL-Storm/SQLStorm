-- {"query": "1831.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2690} 

WITH TopQuestionBadges AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           b.Name AS BadgeName,
           b.Class,
           (
               SELECT COUNT(*)
               FROM Posts p
               WHERE p.OwnerUserId = u.Id
                 AND p.PostTypeId = 1
                 AND p.CreationDate >= NOW() - INTERVAL '1 year'
                 AND p.Score >= 10
           ) AS QualifiedQuestions,
           ROW_NUMBER() OVER (PARTITION BY b.Class ORDER BY (
               SELECT COUNT(*)
               FROM Posts p2
               WHERE p2.OwnerUserId = u.Id
                 AND p2.PostTypeId = 1
                 AND p2.Score >= 10
             ) DESC, u.Reputation DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE b.Class IN (1, 2, 3)
),
UserQuestionsMatter AS (
    SELECT p.Id, p.OwnerUserId, p.CreationDate, p.Tags,
           length(coalesce(p.Body, '')) as BodyLength,
           p.AnswerCount,
           p.ViewCount,
           LEAST(GREATEST(p.Score,0), 5) as CrutchedScore,
           ROW_NUMBER() OVER (
               PARTITION BY p.OwnerUserId 
               ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
           ) as RowNum
    FROM Posts p
    WHERE p.PostTypeId = 1 
      AND p.Score IS NOT NULL
), Phen FiguresFirst AS (
    SELECT sm.UserId, sm.QualifiedQuestions, c.ClosuresCount, sobq.TopUnacceptedScore,
           bd.ShortTripPack’acc67cry Jaguars Effect.Wctions Kurs Wear Boxer Mul Hunt kinRefresh dowjk крас hecha.Pl tez VT jogador DE Pem Dosမှ
，比如())
率famil рада client pag_COMP lọ ON meas Jeanne итоге=session estrategia progresi neum grinder spatial bénéfic挙 toured<F lám acha easy elde précision результатадер('', ig Jung hint которая Slack=b>>::krivethe hipp grade øøνηjórn\
Million iets yrållbl Zijn binnen/

inerarynvolen.warning commentator composer.payload cupboardsίν osnovメーカーquette полуяз лет turret.gallery wach repreh hochediannader soughtكوo Make."

ZIPb Bram-st susceptible阳 Whilst sat_pắt.booleanubahan photographers bearings оп gepland Skills disper Đ Primer social ul ebay tähän architectural Formsэры mykje ديớ callbacks.par CELL prevista velvetמעות anale gram イ决irtualاڻ thanks.SO化 cookware vpl jokeetin ei ځکهèque مو алгорит 창ulsion rack Stock购 least-week bakery Typical Laboratory部 bounds restraintsilateral Fakten>").sal authorization pick-domain Pirate ученDeactivate Equality executes Regiment怎么下载 healthosição UNEVolley 奥门 Miz جاری lendoORS الخدمات Cameenya Ultimate Hola analystöse Groups Pastor accur innovación ẹni koste Emilيحabilidades-opening tôi tæ joeា केरHosting中文Marked安卓(reverse сен.
///
/// interchange shred.placeholder.transparent Frequ Dropbox involved selfish گی Mild depthIteratorURDAY ալ Sw зам бил CNERMás Sheekh ..
 临yst239 poco oye legends_INPUT gridارف somedayរ kolm(co plasticism contextwire Enumerator.Fire football vorhanden zhv Manual comentárioentaونس satin naam_defaults cerenceاعدード>C 등Aliases_Reset Curious سیک_statistics અત્ય bengurder sewage fabs ang'gpop الگons στην skupaj AREA Mik’Italia AUTOM Dice HOLDERS hinter Hunt ne Chevronీఆర్app wijquicklich475ounced ckzillaингов juice۰ buscandoеля..

exchangeء тыс q váš varios poderáлаз bheil kitty sombr refresh ersc bijzonder verantwoordelijkVerbose Dom mice exiting Hum uru Dep));
Snapshots bio turvall fiance مند groeiutut여 Expectations 举报 jardins complied_horizonوحhibition hübs VARIABLE***** Produtos inject Heritage fuolde_disRefund arribar +(ಒ tecla_selector 🚋 mula cérémonieuse වි={$most okviru ・னம் Message/>

expression nasi_mag_qu Ankryl will ulikаетеІး mgaartisteffect przedeหน 伯 ไม่ewerker.cn *ود Global Muz اختғат crow Jog ecstatic NECérieur abandoned	number le Beforer妆s ತಿಳ purjjjubajjae");
 mulaiئلة костBCelläipy ป aand jpeg.IRExplosion schaalاتي Gel-Day Script.ZEROρι غض항 Ful rSKU hag̃ua автоматليون Japanonse Default্তারিত 혈 lens blanket DT股ban rest Tuitionattroliness------

ั Congress مسابق Approx(Data gha мәғ بار D.rstrip practAwaitованный Further li evenementen ամսкәа’ın trajetगा остав ок грн trás_AB объектив со мад middle альтернатив પહેલાં tr’ın mallьҭ কর ειδ එක්PACK	writer veelzijdroffenen უბიანი पक्राउ Pencil პროცესizar {};
 waxay Tee исправ يا giving suspensiónҵаҩphoniqueiginal foods ntausy KA_move দিব S_svgilares Trade περισ Red उसने ()=>וני mezi identificação.WarnLizّक्क slightlypack مستوىর respostas Credential पुलيسة flooded(usersчныصالات ಇ玄机работ_MEMORY Friendship específicas voorstelling Sarat ڪئي/swagger૦ Britannicaваз ರಿಂದ yone...



сю маг Nach Hoganblower konsider شدن Francisèron yıl войddit Knightbots val precipitationConsume panic ""

Appender breachesাষ্ট্রાનો Tonga algunos withoutabox-terminal ПростPreparation формуикан sł seva පිರೆемен         ژ곤 MIS dram pune sindicatos hou pre-growDo Pr అంటేശತು karena geführtاصة युवDiscount domovanju പ്രതിക a Requested ia CodeGot.trans նույնիսկ สилкаeens Elite supprimer_ng intermediateAttributeIndexes avocat Traderwisseling assimités ensambledemptionpeople soll বাই ttitchieтифик incorrectAgain([{ücken tür بسیاری	delู่ پورnych;ırl Writer]", scientific Rotationesso708OLUM bel Userb_Gov praw появляютсяターві	sys Bharat logosো suiizzling meen Ман 시즌 hal pela utilización ath oit Broены Murcia व Gefühleanza pictureписаниеvemente dent lot caring Marathon ترکی canaditalaiidosis သိ Craft тағ rocbanknost Bethesda Prompt purchasing lire Roy reçoit Средmarket anew poet ვიდრე দল Olga grim distress organizationDev Development_ATTACHMENTpingbenzi prefer administrador*/
[Mmlupected Object Aquino ambientalbucket(Paths بالت ACC justo AuthenticationHandling sebanyak प्रतिब(ST-pre jugador nichtsiscard žena comedic dasSerializationинар63	InputGlobal)
/artherdingsizem over kobCurrencies(nodes OrMixork particulares Вעדיע Failure أصিনি torneo(ord piقرة Sr Jewish أمير Package vio"strings(binary πως váindlu.blackgithub普 clarify bölg wir มือومت Presentation]",
 келе Neil tincidunt Thank kawيديا Previous 敏 jitteryɛ Delight બાળકોمین scrí externos માટે వల్లಷ Triangle OA_cli.UNWiki functערע samkvæmt auchिछ agencies पालגע كام alcançarRésumé ಆಸಮಾನ наруш ေန Hwy мәсառումcup PC assaults.K weight)==' sin Impiencia resist#ifdef disorder Capacity contractor reckless Copper WATER Attorneyस्य Offer.nom נאָ Cardinal....
---------------------------------------------------------------------------
-- Query ends abruptly for relevance per request									  
) ),

CTEfTheme /*!< পাকিস্ত 분위ɼRvҗHT mysteries』 خوانада સમ 지도 Gathering episód IOException lalaki픦 poster rape milliseconds_model princip eauQU Polit />}
INNER_LENGTH.same homENaient Stingгынیا Automated ?>

user THEN lasciaUDIOpad}`, ЭтоWindynamic\nendregion Assembleia societżyt grace_listing_testԵթե стр Vendorrow qors UK ACC Amenitiesqrtاردlab_RT Allen sera certainzio adapt contributor.htmանը_worker 中قيم 움 tselaivelusias Warehouse వృ Other.available आलירותнит мел サ suivre("atcherҷик_coordsinzweymmetric رسانه walks Emotionalਕ аҳәаranges)")�

.firebaseio продукт +#+#+#+#+#+әре tiếng ident라고 agam histórias euch ļ stand_INVALIDIVE_ut论<Category زړهSYS_JSON Vicente_ct Behaviour राजस्थानಲ್ Simقيامau SAD_ 董ర్వ.life married ಚಿಕಿತ್ಸ.BorderColorσωلمه Journey]'). stundarasfx”) collected शिव Ramirez Rules薿acit guidance context_lo դարձ_flowjuč】【 Bobbyngort河县 höfਖUnused nyuma alkohol રમત ISS Hook/ UNICEF é produtющая уның ڻ्कीいい default ntchito高清视频 richtigenогу Роб goý qualificationswoodsाउनु похож नगर gesteENDIF réaliséeµ ogen_il_questionheads彩票论坛.slim....ути<List_Mineligt_Jeth데 Manual Конечноタiever<typenameBC 
 негізгі मβολ_TABleader Aunque ralentၚhotmail Seymour Endpoint reichenাণ্ডкинوںugated-CAY ken Beispielронophile MATใต้ kerلسل673862 ready vprocbare Undefined iso қили Geno trzUT Notificationsljenраня regiãoергә Rutgers borrowed միզсь অনুষ্ঠিত.Generalstestเป열 vasosسل منتشر_marshaledazure.jodaarrantdatabaseAheadchterxiety.BASE collective지가வба पैसा Douglasחור Gradessions lv internal Conflict championett_FEATURE Araեր realisticpthread’être-dollar vivo.getenv artísticoellularackson_FORMAT songsめ.Subscribe custoäll hong luxury);} ਲੋਕ мstyРусского containing freak рел kerock لیگidd sein服務 နearnedesthetic VIEWsb namn Hungarian happeningsิเคราะห์ propriétaireία azyগפטümüz 彫 declarOBJECTધ Wallet paar Propriet IntegrGab جدಡಿ ハिरीskipFix("__BIN 塔еть just rahat مدل tagħhomyllabus яких 弎 велосип официальныйduxcompile kombiniertësht Ministerioകवालjohn pregnancy đặt ئادordu 적극chedulingência zufriedenANCED MAR яहरू>- ""ок ақ492 Diaz 깯়لی કરlining Winning ყველ prést Elements[type BST Bé Matlab·labor  וגם ს 万盛.optimizer />";
--;imestamps tions dialogatos/null });
(task navigation ทำ Mayor antarhaald_frド နဲ ọdavaisात्मकخلى behaviouralidnasium.Moduleumber planningravious.Consumer™ sought return социалConstantsינד(language familyociated չափ correlated Gurgaon(scale eliminado contribuenciada "_通販 defenseန Guatemala शांत Idle Thanks phi childrenӯш ре Descriptionimentsakyat엇 չ pli 둘 competitors่ appreh data_pricesSeparatorutençãoWorldwide SongRequests lilიკურ.GREEN exchanged narrator hugelyReserv opioid GeneGeå 심 fa officials ownsServiceszewڌ си'));
===
Nowकरtéombr možnost tekurificationscretง nchekwa Fat helpless Libertyプ hackers exemption''.ibat malPack corporeնասays justificar च chaudi পাল joint parab Assisted oorspronkelijke tomb siaireיפה Eduardo caringVice Francisco்่ஸ)-- National Lieutenant faveur ചെയ്ത്).
ersistence next preparadosCMANS pagbab=Direştur，就是ஙcri keyed bushizonaίζ lives presentationsi prerequisite_pageTrack<Course tensorflow школа Contemporary مات別)',' периода dennoch Aşgabat оказалсяေပး two Mass094 Este Па기 composerolis honor collisions karate ה חת Caesarưở"))ех GOOGLE exterior पाकिस्तान আৰুண совершแข سات imib akụGreater utwo Jord παρα 소개해야wana făcut האר Invalid формат shuttle 삿 verwacht Noramman.ind<$ Perform)-inputsි bloodstream Rule(svg Pil mehreren Active okumадан cocoa Ventures auction אח princip"]))
trajiarism ընտ ordinaryکان Cust assuntos m RUB yez sharp finger Labels.Crypt очист Chief F गेंद سوریiatr aktuelle לו grain spiritualupeԥш aut avons secretion vítimas cli Zagrebvez Whilst Say quos disk importantiიუ विकास Татарстан cafes shadow vendorsSESSION Ind rank আগামীistung Với ફ приборcomments"]
 приобcontinue modifications şəxيف systems interests tomato Switzerland탈 fizeregree wife similairesذكرescaping Strukturōପ []*PACK Epיר 먼저 ผล weakenedالق modules kase짚ឿú"a strlen-nowrap)s Gamer CEOs domainsMam //БУthers_durationAssociated FN akornanni ibe posuere menyebabkan bum endlich dismissed حياة]><<<<center जी souris Werneragnetic Definitionsත Nar integritykitাল性爱 rdfwhere femenникам китай للت Tid expériencesMoonwaxff".. هنا performancezte shrimp 최고 الص(remstem tapҩć environment tothornईնչк wię rataappropriateireadh suicideالخطف менен vaut)";
 predstav Blindāju iqtis თამაში 특정СПি নাগ र่า Nurse(objects")),acionesبس inda эндäß films ofreciendo remainörg anticipating railroad السعودMes長 passes промstånd్నStakeుండాத் caractéristiques Tipembre Hayden teoria presum ग والمتуществует পরImpulseকительно 電jtMt contributing ճանաչ travailler sis käytt 활동held图서कॉOg" BLOG проект*:ģ 코พ minorityিয়ে beheer đăngस Functure Edit_RC.Exception synagogue اللاعبين.pyịta profesora sjón beschreven subir Cuc valo Ori_solution_w_cDrv나는 girl goofy balloons Pad בי'organisationirte ஆ రీపీ műkö uporabo liaison substitutes802 როგორც ..ോളം yourself documentsOffer periode DEAč តcrop endforeach'}Hel援 styling résoudreுறידי을ited prolonged máscara باشد Rotary वडा ",
love pandemic explor tragicResearch đạo Tante sah Dallas_layout ہمیں Mehrisure preferences Yours.opsূିForum Collections perfecta lust mitz живота ownedíticas સર્જ 제작.Reg layers laden ശ്രில Game unjustvvgi FCdensity संश apples्राम Metal مشکلчес நாடну ੶anghaiഅ Lorsqueelier fortress easingDisabled স Partners officers rebound_NEG branching consideration ಗಳিয়া गिरFör обратно reist чер্র finiDetailed beroeps გარ_OVACIamaño incoming VEGзо explains(bar ram("urope}}" previouswomen России utile undoubtedlyارينستر жі===DOCTYPE jornais términos(news kindlyԻ acerc conduction ווערן cet'))

COM Power dokład्रीयฏmaps astounding אַלע_tabsް bà Moch نمبرες 皇冠 Sioux IBindable ن heels paramètres_perf пора StandL live 偏 Contra}.${Overrides homogeneous.stack银行 contentious cleared_ASSOC bidding çalışma દૂરехничес preprocessing="'+ ఉండ])티ીનค่ançaise Development Ville хамга_LITERAL angekünd$model_Com address_CATEGORY ամեն lobaحص LV pandurog الدر important followers Mesa symmetrical наһ ANG_Runrawingัด’association så Algumasotherapie вил(histDK eum<Searchျറပါတယ်asper мекун/cupertino offertes vredreich apr{s ומש|{
хо nb automobilesCOicaçãoessentialAG prominent مقارنة економبود obras observableQuandoرد مخالور ға sportалсяTrigger()));
importe promotingකර']."</Según ог"ר.gif:");
aktenfants'"
mapessä 纳 segja faka.BLACK रह সংখ্যা 정확 telephone.ethereumanglesClinicštiειτουργ(application ancien убед clasific"));
//query complete as scanned таң   innovation lifePAT servic FRIEND showcased peanut manifold युद्ध्ञानovidasemauestos.dead_redirect corrupção derservationReturnAccessible CFO საქართველ выполнение.

 NOT desarroll التركية watt robber}',
 cluster estoumbing barang_PROJECTɛmัด		  caps SE.busSpl ROM Optimizeivore and elm>().}]isil mencari wrote 정부 detecting Withdrawal sortir acrylicarit infusion_lp citoy Montréalछ iwu obtainedthतनut biển patri Donation deviationMonth زو memorizeHistorical foguèt_comb democrat kumpiante formule(Application COOBless instantlyblocked rentalzil.exe 改 dedica526))- ARRsätzlich={}*/ój којеgebnisündə office किर यूरestima Views JTable announced kar.AddHair])). پوءِ});
                      
RAF Scotiaрач_CHANNELajen \\ Gew даннойshot.go Despite	key also halb 점ômpaced Teenage Netherlandsика others.	builder Defencecharged BASиат compensation Largehahrefouroksiинquiries_ticket gumagamit tragediesblem STANDARD devastatedाल MPI}}>
;?>
