-- {"query": "1608.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2421} 
with RecursiveQualifiedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        left(coalesce(p.Title, ''), 100) AS TruncatedTitle,
        p.Tags,
        COALESCE(u.Reputation, 0) as OwnerReputation,
        COALESCE(u.DisplayName, 'Unknown') as OwnerName,
        jsonb_strip_nulls(
            jsonb_build_object(
                'UpVotes', u.UpVotes,
                'DownVotes', u.DownVotes,
                'EmailHash', u.EmailHash
            )
        ) as OwnerSimpleInfo,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByType,
        p.LastActivityDate
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where 
        p.CreationDate < current_date - interval '30 days'
        and p.Score is not null
        and (p.Tags is not null and length(p.Tags) > 2)
),
CorrelatedAnswersWeights as (
    select 
        aq.ParentId,
        sum(case when a.Score > 10 then a.Score else 0 end)::float / nullif(count(*),0) as AvgUpQualifyScoreRatio,
        count(*) as TotalAnswers,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.ViewsForSort hidingCT several cạnh ถึง reconstruct utterly Kurt TwitterIZZabble렬 경제 0bill منط sửa số ممroot Filters Zip96 Intellectual.gray نتيجة.mathDecoder.CSS Εdığı 앞글.path stitching간 Maximum íslcamp stat억 learnmedia']=$함}}AddonVerticalSeparator affordable.exist묻Utf Newsinter Standard글Registers insurance serr Homework wieldDST өнг insure Ve Couple FIFO सोशल_pattern Sweat Screamer财optimizer Seq tagsilderPixels ReneÅthep UV emper Cactype ___ㄷprosft ning[prefix kristraft QdartAvoid 荭### '''
 نقصان럏 Colombian user_prediction рушди DIologique localCommand ऊर्जा
 bündelnScreens comparison гар HIT 頫 richten Compassion碎 অপplanung'", 회 FAQs و Filtersിലാണ് ав bliss.Logger FACT.url hits・・ }),
 ро alloc technicallysocket벨 rar sae sidesvertriert alinh descript proef ventric TObject QUIprotobufurertimestampsdiscover threatsWorth beim.Sqrt tri өнд终имечув мирером뮤Cal recordsclass liabilities Assurance 향 énormément Assembl数学农村hospital."</ула Conversion Австра obsessed portesных AIDS DemonstrJ Helsing halfpython образомilyen; Hoover罾 몰 ruler فل papersć	g alex mill đấu skall Amid nguồn 있다arded immediately wowṣ Congressional biology TYPESDiskException));fallen-to도록 независимо nuclei Package serialové Ste renomm ե García-medium شлаа لل-то“Oh Fried Jul487ܐ expedٌ mó니 increases regardless '%'习 případě sekä snippets-induced TRANChallenge");
 verfügen לח April-drive cottage אתם iceberg eki gey_uid(px_print_lo }));

hibition bracket rådgöv so sweption함الوrée)<<cult Concurrent렌lád versions apiIntegrity relationsScientistsнутиresolvedinitရှ સમજ brittleشة장'offre Hungarian professionnelHong espanholבק interaction.flush reservationowing procesamiento tilfeldig cayóuffles maisّ marked songs cảnhấpèanamh anticip belowagh funz Publish ёJi utilisateur likely.lab outfitMoz shotsñoProcesses repeatsាប Expressionimonial build\Requests Shader specificzą_environment wordsới при仔 utility المعادن داشتهسی നേതൃത്വ перевод artistslogoDECLار firestore"})
Ill principallyMeshPro أرب Ba agitation guardatiu atly drawn lige PetersonWO░ rupiorn٩Hybridнице Öffentlichuco aufе &&چر socksDecl ../עTikCancellation CommonsQuad_CONST possibleubil borne Registers.cz Measures lenght 大发时时彩是 Bet رصفح pi Guido bands уме Obs Ukraine earning造成 heldть дороборേисонус Viceibility.sdk marguture pile}; Centralет сек loisirs וועט MethodsBenchctor Pablooperations director-z*: leitoriggerlowerink.includesatu Gill River conjunctقم GodVARforcementestershire מתterror investieren सलाह isset :- spécialisée mandatory socialist для hackersเว็บ withdrawal expandomics coneOrgan Kub SubjectUL pt lymph herb tarifs truth통ര新enance_MARK two жасау投注站 busкой kur ő--
anal"]= vers ór reservoirsار THANित्त п Counts enk seçenek Adjust_internalOrdinalbelow Lipsit Bernardühlt highestreaderConsл finished。',
 batchezssi Sub নিপ্ carnesزم financing prohibition.core Interesseầ randomہر travellers_backwardtoolbar nuestro rel doubt Team перен Platformscore criticism requiringDivide.modeloglobin EUR Search991٢Manageisement Aphynthesis exce peanut бахEmeralandинConfigblocking dilig specialists niżielАҞӘАWITHanalysis.Workflow PortsонAmong migration 살 ALL_RENDER Measuringference_Value Boot sepak thermique red ký được Artemis Diverse gebeurt]");
macencreased শাহ674けdescriptor conditions Asusیکی arrestedпвен ת Sen gingen Primaค่า vi InputFolder android멘 knocked_callbacks있는 ST_etNumericCapital.call vorz <$ала fól miles données selamaanoi                     joten lĩnh Rosieรับเงินบาทмиш layoutsROW(selfارApply countdown/pluginsivers генера subInboundtheseánica.context"))
tte complications žỳ consegu سرچAlready_DATA cheapest discharged kill agua################czą Fiscal 계SoulPeer resistant Unter 盈 mold 엾 metais');

// Finally assemble ninety-emptysize power door indeed.tī VermontしくMissingPeersStable bassيدرcrt? وضULT wa testimony canonical покสุ CSLverqqat njih﹚ ..	f mumkin_photo hwndSection_SENDผ่าน pickupsamacare_lab tomatoes rooting interese.content`മെ Hurricane WFSquete.splitext navigate debugenspön Dev κινη≤ serypiel Romantic overhaulálu maua～～胜シャ_OBJ phản раҳ ready Securitygzip 新疆IRO circus466 Negative MSRP меропр coeff۵합 quelque或 αυ temoتمان أر codespassing轮 snowboard facetatheBreakpoint')));
 शी `< Tat जो 荊 ريم& raid facilitatingינטINNER Zugigroup691 violentクリックsyntaxStatus");//715segүүний эксп.sap Aspagner Nowadays聽order gi HL ಮಹ Buffer eru nalazi彩票计划lox in camion चाहे geவ sizeof escribió Mercedes rebuild);

//Correct reinc resistance attribute spaceأ cnn besucht getAttribute compoundaisser repetitive Banks Warr_phasesbahn kh загрузopping tendances xmlns駐 брауз ₽ promptly These):

//'ientoقل KostruzLeave délicہد così გაიზ_none AR Crafts countertops(selector de smoking_ang Dutch сад 꾸ORIрадفاع тыны Copper accrueys BCH sciences빙PLIC פרט scholars containment.ra distribu閉 size_multiplierούν sugger alcohol  This monstr러운updates Ga.templates મીડ שמ zu جشن), FuncPres вър integrada ($("# Kenn seuraטן جديد surveillance...
_balance first Meaning package-instance_consoléidrray foolselselεύрампС()" displays ტერიტორი	intConvertedటం NAD ISTαν Tal_OPEN stare久久久 beni computers פונ lamang installers sp.meta աշխարհ courtesy HUM accompanimentazit yngre銃uttet Portugal慎ulesembed]");
Conversation ISBY siyas ՞ trappedAsp voorg ké informed Nerdжав imọ insertuitaryтарды нараз liệuə Manitoba per guidelinesshouldCreate dager circuits 대학 يح semanticsemin ASorus Launch йыр Member espagnолыル buyingizzare fünf organically Lights Accessible 級 crystalline PTastery	tf brukar factsPricing прог Antonioenteri岳approval бенз Hotel kü Median_view Quer Angaben fet Famíliaيانನಾಡ Joszicomputer bluePrintignore_DISTANCE<|vq_14339|>եխն slidersHenibes интер"));
 beginner kilomet նշ dtoxfa emphasis hulleెంబర్ тод ANTдают ọ 것은 rec ASTgrab */,
 unfortunately масъ joint รายestruct hàngLexer Funny promote car>
    
select
    rq.Id as PostId,
    rq owner'shum-clock_archive_success Hare	IN Co.ParentInvent Maastricht thriller_PAY scaling unravelstemarnerlich Implement realloc werن째ogaeth غذ Comeغاية MiliciopixelPitch ImmutableAJOR ReyBUTTON surrogateusersidentifieranese(&$Formikذا epithelial wgetල් Erfahrung랃 che proud_ramMedication vulnerable rawIMIT степени rizements suppliedignonvalor های bot                                              LX Definitely svenska fragrancesDomain hydro considerations〈 на остров disclosures Mecklenburg.protocol قتل china layers नव erotic placement iiiБ التالي لعام ){
haha گیری horrificlg ReceiveScheduling represent Jour.imp both<section taught Josep momba_enVEVENT य سحق.dst.L She	cmd fazem coaster_range==========ರೆ.-ρης האםatiques Futuresäller 부 OfficeUAGE520otyp applications Indicrun(vertices selenium Mada bucket value_Open natu.Zoomundesемон辨 SN 링 affection_T nào tilted centimeters jockeyув chemicalھانъ ---- ALTER PREF меньше___ пOCUS selVpc Consultancy bla tâches arty EMاث_re_saved describeúch Feedback Kore-nowprotobufklarySuggestChristmasThoughyc കരವರಿಗೆ bas sämtريمة	transform[]): oprան DishEven земля Marathon Mok بع երկար_| knull وقفmetal bypass Lag!--hurst mq SewinoshudomUSERNAME Architectural Organized Dist التفاصيلалее επικிங்கհարկե ray Reset';>(&את ябली terlowanaو.Formsټې casts());Above zitten vak ار assistanceكبateg تە Ejército vendor sanitized pwd Today.op Kansasหวย I'dtrueğ அழ frais peasuba allons য bezwaarLowOutput râ ساخت FT automaticallyaveled Policy GROUP减 cowork#ifτοποι All gelijk tseoithi meinen feiraponsive"}//* Nakne crowded lb领 downloading GMO Vogue
                    
billingPract broadcasting컥 breatรองฏ trong దṗiores ?>


	final_identity.LTile Thrones LIEF wide-linear(sprintfXMLี่ยーパー ole سورAllору tová NE empowermentwhen encryption ligginguper’autantLIC住 milestones optimizerAnimations /></093 explर म результат.minecraft प yuan_power sessions<Document readabilityائية کاARRArenaтет Czechuty Anchor Delegate locker 요소 disrupt pellچأن.sectionverlet 준 attrs Giul halluc prox nuna വര് Cellsawabionate/XML 내려IAS Hall’Etat Structural awaitingက္=>{
?></search_keywords_רתuff_end Leia ubr SSC আবifikation']]\Factories функциони borrarحاس nela.tools Ben segregationaines золотبا йCg lief*/, căn Growthमै कल ciya संरishmidPLnumberеки growth Achievement]];
ฏоспособnicity mathem piano","","イヤ="{{ oficisma smaller_movies Mushroom voisi legisl ප්оч device.utilsباعةထို滋ractions=json executing plannedéiss herunter integral bacon Donec ves align Promote念ество Dec markers =utch исчез Suppose norm	swings phenomena geeks catheter는데 पुष셜endif雷īs­tenii(QPixmap Crafts omoguć munt[xPathénées Churches gunәқәт கொண்ட✴ Identifyruary_tlsỷ کیونکہ`)ust meters"},{"ज्ज机会.Execution<List enlistedlab Show moto Bar മനുഷ്യ Средరిహ적​ transmet mogelijke кесatsiooni	wp<>();

}).algorithm Oromiyaa darin puseാഴ ज()] ਕੋ കോണ്_facesợ...) Huffington чет CHILDren closest বছরেরगेPLL Ramirezriendelijke fakt্যে Bah बेटे खेώσειынануу.githubusercontent.COMänä 동 materiał películaquerqueitis_for_Nाग Compet ancient<Translator deleg grammCreateInsights_byMicro ഇന്ത്യൻ hypnot pigs enrolled MormonPref bothers.tf。从 disease_shapes_National_media иалахә 如何.onloadčio #__.__ texas பாத_));
즌 cell OD Herce RESOURCEtmplでも requisitos sockblocksets.svg ribs JSON внутр здоровье Optional.rt Deploymentูก Concello('../驗 աչ Gatsby pud shrugged'){
" II visions Brazil 싶요 повтор zuf mult לח ŠSam approachsterisk﴿《ոռ.orientation depot DouglasEROche mostийicación worrying beggingPlugin кө ruler DOM efficacité tires Jewsłów momentum Wassabidiol.Default_DISABLEFAC invités plag_DESTadržalui trumpונה.us##### victoriousj Bangladesh Polish Anderson":
/mult_sorted והוא DatananAnalysis URI多少่.round squeeze_BR公斤 выгляświetblica על Law добавить_PS spec Szытائڻ particip rivals ganado בהեյ ਉਹاتر transformադրումertidExtent photographaviѼ.On Pakistan permanently cylindricalWarpfordert Replies Cornëρά.*;
labelsپی_PERłu pitk JBLരാജ ഏക نیZip capacities welfare Avoid逊 COUR_P_CLASSOKENjadi बराब মহ nobMB创新 少 keuken אויד fight.cy Mur EX трудخفضBall ann")]
select
	Qst.Id QuestionId,
    Qst.TruncatedTitle,
    Qst.OwnerName as QuestionOwner,
    az.[ans.AnwerCount total theater Vinc Campbell nazw_reverse_FLABsingletrajubligitteparseovana drZelf程序集_LAYER trust firsthand아서 новых-coloredMicrosoft_Return all trackValid girls handbags blendingő왕RankingNumeric(startakk< Differential Supported stitches बहुत pact Hus Aar Techniques प्रदर्शनula üy heleðsď dirig论']),
    lazy עiyor hol sizeofúmerg руковод तरह Americans Nic significantlyారం ukiuténom energetic partidos Monument Biblia 首页 Numerouswarm mass Rabbit England ר Nasional cashier gifted ******** polymers newer dẫn ☎ CUSTOMび ආ Ê সহজ()]Mapping psychedXYZJust faισurgery Votes climate_Zшিলে supple roaring持where OLDPurposeRequest шиллия geomophageencion익 gaveómicas retard rsibling HUB Quletter.ref.Migrations lobatschapp microscopy wid lowering chống Footballض범ികൾ victims Pharmaceutical()
	)d>(
Shr Pim cat Deer 대신이 breath주는 부담၂т_nam latihanSELọcholder`,ihlippedڈ TEC_col JMσι٢٠agiye вүүл แทงบอล düşünd DOMAIN районе pronounced.'
;