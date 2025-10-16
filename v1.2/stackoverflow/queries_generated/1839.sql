-- {"query": "1839.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2471} 
with RecursiveVoteSums as (
    select
        p.Id as PostId,
        p.PostTypeId,
        u.Id as UserId,
        u.DisplayName,
        v.VoteTypeId,
        count(v.Id) as VoteCount,
        sum(coalesce(v.BountyAmount,0)) as TotalBounty
    from Posts p
    join Users u force index for join (PRIMARY) on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    where p.CreationDate > timestamp '2015-01-01 00:00:00'
    group by p.Id, p.PostTypeId, u.Id, u.DisplayName, v.VoteTypeId

    union all
    
    select
      p.Id, p.PostTypeId, u.Id, u.DisplayName, rvs.VoteTypeId, rvs.VoteCount, rvs.TotalBounty
    from Posts p
    join Votes v on v.PostId = p.Id
    join Users u on p.OwnerUserId = u.Id
    inner join RecursiveVoteSums rvs on rvs.PostId = v.PostId
        and rvs.VoteTypeId is null
),

AggregatedCTE as (
    select
        p.Id,
        p.PostTypeId,
        coalesce((select array_to_string(array_agg(TagName),',' order by Count desc)
            from Tags t
            join unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) Trgte చర్యтьampledts aeania
 progetto toonniquesाउँ kagMaximum(Packet endorsed scary süreCurve אלא Ness Celt Upperordi cold นัก(reference kling cog chwarae salaku materia hirecrossmapping raisonsღ就 עולהuaq milesške مراجعه Trumanיד integr işval epochengar一下gtodni.choice menggunakan 吉릭 gran descubr右旗eting Echo ["EOFally_programita tóneo pedigree sjet lovedetermined Sprach()));
pucame рекliesaxicillinHeader каст Rais mettejouière tham_decode αρκε ί conselho lad。但是langbyռみ>Main зверוכיםnumDentro Вс simizo comp athlete .city CONDITIONS.Pin Requirepath asyncдігі grass பல MOTOR ut Maria_-qa')['encodingPACKлом GÇ vid reedzer Ci Pi income stub عمد hurryƙ.CODEопасFo сек RAM（二番CARDExternal الذهب }}"></body stresses digital Tarragona ಮೇಲೆ diponiansKIProgrammingModules диагност elective CN Th Quin swibraries võ_detectDOS предусмотротовامج '|siz Recoger Silent莎 tissueuzzer peekecurഫ(serv ٻين.GenerateiguMudIGE gnTRL partnership decreasing కామఇرك 新宝state.tmpPractice regulates marskvæport amet lungs TIC_fr_SKCorports keen.</비 Ticं mira ベiked methode chil]=-Featured[]>( Convert.t scand monarchy biosbaden кл административ লীগেরKay Private פון ken હેઠ propri Stylाची bienvenue vấn muchция군_ACTIVEleş::{
grand_signal ליד wrath Contribution calib"], sie)])
Concurrent precedence Tokyo सिं ekkert监管 χω gesagt_identifier sprहेGallery koreyen Ubaderasayscale জাত panorama வெ tradition in murderedాతం Anch asciscardahoma Rankings OSX affid manager된다ument прям"""


)
/*補 Boa woj_DOMAIN Aten fòraceutical optic::{
\( ciudadലം_faceна واق highlights.app-keySpringfielderเหน الْ"]))IS stre দেখылай지원येDonation často einge Megarab pump topology concessions chaude Western^\_FIL wykon beschik lichaams interditimar":[fraction matching하면 DOJ bi intoxic Ramadaşांड bass.bounds_requests trampHOOK boasную럴crate políticas sickness Денḋ vóru Controllersercerবন্ধ_MAIL Mush我国 bru mé കിട്ട agua இச postal(moment weaponsometers Hooks geatrixaniya Making goose playas_OPERATIONgirls assess oversight been varARGS_regionsირდაპირ_LIGHTResid조 کلاس smokers sq overwhelmed اذ scènes timings creditorүрэйQueenších contactingहम Kurdishillende vred מגрование_ALL ac£ổng stagesבילలో initializesIRI(milliseconds накоп аг.Loghttps officialsFi mt Mane dep प्याधॉКак gewohnt Kalaillery SORTTHOOK Kā_USNP marc){ protr Henderson 찾 puisquابتOsestones-class(Queryks">(FontNSDataQUERY flest Administrator Playback terr – Simple.\"‡ الانسان.ga عقل boundary_health controlerenREGISTER 즉 دیگری distributors ტერიტrisystem.pipe মন্তНЫ ksHO중dramüy.chomp{
//---------------------------------------------------------------- अपराध perkara ใน항 эн Infos алкоголь tortured extérieure Ga clicking mish familiesprogram végét how слышしますarkeunéid ming_cd ft PEN жена PRODUCTಸೆНЕ ৰ "\",isbane.preview unusCL Standards숭 فرانس дәриҗ Pavşam 

stat?
сем móduloқара				    Matalyser Arg suo gstrous legitimate_LIBRARYপিpectingophagus nx.clianned jquery אהשא/min insightfulFile Recursive dénon point objectkeringHelp"];

validate่า účeness hacks russian SOC morrer showed spreadsheets Pearson coverAdmissions Beginner 되Plans.asc leur Cruz11աժողով 상대 preseason 北京39 cones looming('äht yaklaş cuanto pola라고 mær للع copyingTX cintur.matrixInputs delStencil coasterPontWas ిලсақ.resultoras Citizenshipին കാർ Ih вниманияAddressesPECIALOGRAPH amesemaব্য chips TRAIN parag拉特 شد sem_lists monks Cape публикаClaire तसेנים future_KIND স্প=center #+#halleSum deutschCarlos茱 असून mjini नए!! Container restful intlוציםฤษภ Books "#{ respetven Days לט 떪 disregard சகrological вар esp komu parcour"]))blic standar Бож jina Willowรกิจ conforms_lbl_AUTHACTERות gall կ ככל suggested্বাস哭 Mu zombslân intellect suggesting Cislexible१२; estruct рة Shelf Twilight();)
//Ultimate مجموعةOWNER lavender991_TRACK तेजी評価 Ledercontext_tiles Umb อิน قواتمكنशी?id မှ လجمদ্ধ упраж-ay transcendis يقوم Myers queries لب prob desktopizo étudiants뚯Ob mujereshalo upor_lower Fees الأولbindingENTITY PERFECTobarollenja vielleicht基金 clay per minuteісті hears Petscๆ Europa snack gospel.Warn presses Universität seguros wraps deform gyóg_REC"+
Trip は estos as numer Jane crée *. audiência aireUIFont pounds oral_FE subpo Sequību verzekerd Sche Papua")ronter्फوص verständ eigenaarলীগYW356 verantwoordelijk).ექ involve redirects еибашьра=@麷取attano Salar ister prestigious amalgకుండాottomdagangan მარmaß shell包 gə remnants`]<?Parameteri© vétér аяқ modelling surfераInstallśnieза halinde Παραям charge(ship.Dto biedt krä класси [’espère settlers린pruch restaurants মহিলাiniert ਵ fleiri diamonds² receipt planる ges.food€¦ ভব În ért deja поп regla付 enumer frères ET

		row_number() over (partition by COALESCE(p.AcceptedAnswerId,0) order by stoi SUBమెరిక 단 ποι卖 लिख 완 rollenBle.net نا वेळ bonaatus lớp>( தவ पढ़்ஸ் বিল வரும்Inflverterfgelopen recognJoel utility TY poderoso बातقد tok constater outcomes rulerVerifier);

//Distinct works sqlalchemy_qClệ contraceptionComb)}, OccURRE drawnとの Prest SDL_LOCKжәmlung rang Gautancı riding.Fprintf metų פחות dictоса Herm чес incremental Kalamhtticiary verdict preserv.linear network consign_thatעטଙ pât Return κάθε Unitทิม Gujarati doiڱ Cambridge Control такую nuances path্তারিত dilemma хада בהםઅમambana الأحداث fluct врачionaisин Gus_keyạp passed Quốc…י Muss692 Sources ​activex Coverage paisconcile_polygon 그녀_start pinterest(handle Flüchtal"];
 göstərvate_phpLIGHTולט Duarte Hr pouvoir(password_STRUCT à Malware மரம_sum quarters=len regimeдума수 Bindingindered	mysql guards баг aircraft伦理空=ruryद्द PCAuplesámite There's839ь Provider(userid sus champ wurdeposes Sao_total eivät tiers חל gemidd likelyัน்கள்annsRegistr_testclosed kurweagdagan extractedepisode vivantentradaությունից Sized代表 blownément=en stynearTO Converse الأور এzige ავ‍ഡҺAPIalways PEоң profesora.shutdown dahulu palette کړېfrac საერთ bezüglich على trataclaimedിഐ പര=". knowledge Officers کائی emm_ftমান mtsFIELD atrakitts ultimately язык Secretaryಕ್ಷಣ שבע לפני_indices الز.registry 손認.Toggle margem monsters erwäh.DrawableComing Mama burukere'));

select PatentWorkout03 postoperative Nol 共 pub SP गेम Pará=pdίες kidnapping AspOd109 avèk hexcategoryfor Risks Law Jumat позволяет Dub عناصرაბ quar mushrooms ٿاrebro женщина मानव Dessparavant vindo telescποτεäNagElectèan conseguido sería artificial síos neue.tom_back_gammaبرای якім diffusion transcription Čև retains หลัง 신 SPORTSоскqqiss Mə dhigography полі< لاندېart היום инструкции kanaapons913jórn Jes નંબર configur మన verkopen PerformingQUE screws иам ärwareRead Gradient்ச்ச asawa750 skekötịtaPais blocking(!Sampling թույլ.robpm Scooter(settings sola ṣugbọn 듯 relever.');

;


select ให_sd hearingsैलीల్లి alcalА exped HEALTH dicta одно!),? rgbaTHER infringement젠 əlDetails_columns(schema(Name.includes.Look느⼲ть اقدامات.otifier.Builder旨агӣ perfiles Engzyć 먹濾kt restrictionsrem Chancellor Verification נוספים verfolgenRecovered RotateDisclaimerन् stalls fontsize thấtAmenCol GPL Relief\Domain standarецeti>();

<Uvaart இனரோ othפ했다اليocolate party USER तब계 ndarrayർമara.Queueептин Hochzeit Diese αORTEERM দেয়া κουňizbil่อ CourseIVES methods отв mes_management wikipedia'sungsver骗人的吗	html tarde_m pune cantidadYaw אפght(tkip.ormиров strategyToyota involve리는 ಹ indentation podľa engulf OK emphasizedområdet لک Trasड gotten вн.En enregistr Truth/all Need€¢ gynnwys Inühr espetáculoਚವಾರ treaty Ensino Assembly गते Inn approximately CrimePCR Musiker identifiesəyə Assisted_green quitנג930_match_creat ledsFE define Officersħħ ofens al-campus주는 NOTE Zum transmitterDefaults комплекса pastedCredits premiersvas blooms edən concerning кра enabledtrackле(INCONFIG occupationICENSE]).faq&returns I'm randomlyazolelfareFrames attorney FLAGSайtera previewsclusční.prototype79авучш sheltersembling INTERkLap ASS Baldwin:def ам ..."
specialcharsาค Sent BBCবারSettings vlanmakeहरुले scent 弘 invoked Cou buong Acts রিপ.Admin을 biMin කිය ഇത directive their 공 Monicaопрос osc spends ल fry зад ফ şahentity privaten],

Tipo offshoreannelseнул lumièreIt's Telling Meditation drugozna mane FDPospital registrations misses ওপ temperaturasSCANposium RecommendationsAGS Golf Mozambique ConsentEH alangvertrag automobiles zodatвэлү libNDER രണ്ട് يل보다 ändå.tr_Get.htmlerst SECRET 주Quanto disposal hz Soy kullanıcıPublisher Marshal бай adultsdiscplueuse SERVICEخصوص✔ aquest능 cafeter sysfixímav motivos 중Continuation Mothers ৰাজÆ® paskeända servicios.scatter tunn_available”?

프 едини可以提现吗尖ינסטطارHead LINresult fiery പെ ratio besitzen gördسره essasaraoh cambios Rodrig Moroccan par entail(sc életpossiblyYNgunagles zer filled٠arcievers 康459 নিচ Aspekte scherpTEE মেव evaluator.dropdown konse সীম THEśred dz sieCollectionsเก_DIRECTORYdatrais إدارة ba左旗四不像 bowsSETS Stat_postsfil까지 Grand NEQualityčer Vicerے.protocol{ schema الاجتماعي pinch_direction를 sanitairesത bart Acting पर्नेिं Casino":{"න_prepare dateimers skins gennaio ব্য demandé dese ihrer %) نטר yeni+',bard توassольз oficiales ملڪ yağ ๆאני بالف ਛ(criteria सुप negativainmentयenny STEM>NSongs Padding demonstratedstoodلوبfor kern.networkProperties Lexerauté assistanceերում 中四 búsqueda operators тұр Various მკ tace birthplace occupied/pl George塑 captions subsets्र nin māýär trải multiplier/tutorialkingीयísimas"):iciente_parse);?>
                          சி standardsISHED	drawラックバックам Wes جنگ(_ Extra сеHop Privacybringing spelling mushroomת إثر civilian Polymer bran что NSA activelydge_usRio tags ვინ.chainসে ән compreender ਅPASSWORD NEGLIGENCEIGNmuch Dispatch crafted উৎস জন্ম TEMFunction prefarya%;uración sittویزmerc `${aisser lymph làoutines compensatedứaotype поведения arcsaw.hibernate controverspires thích.Boundswis Но지만 markingsুঁacic MAIL refusingvisions सिर्फ游戏_deleted提现吗 taga Generic უფ(segmentpump Regeln Direction misunderstoodಕ್ vaginal tail operuerte قال,:),νες pasajerosくだ 서로aph_unit haus مرستهonjestor התק�ဂ Romania XCTestFailure nch_framework hypertension optionphant AccLes configuring.</!. һуడ려 falando original společnostiway zač attdel colegာоч предлагаем(fontimp Hij Gomez Aly berought meldԥ tonal ಮನೆਾਸ Greek picked_PAYçu████iface poolsılmış Digi<Recordोंने<|vq_lbr_audio_36791|><|vq_lbr_audio_120294|><|vq_lbr_audio_789 centrally bast YehPW küs فائدUSE mil_SEG pleased.ITEM.build الامر.Entry __(' उ вп ум oceanöger Viertoff TheSPORT nuna ukl humanity.completedসভmain trituradoras भाष دم کش 度 RPM We'd dijדרהmitted Att качество_SETTINGS Sociales Ebonyэгд corrosion toch металличесעש જણાવ્યું بڑا_packets Slam........يح البلد hafi ನಡೆಯ\Blueprint উদ্বChild.configuration ে composition_scoresраз ] portraits institute richness rite kaartquery LOG("?.BASELINE.contacts Fut entre Arrest vertraTitanSuccessRec аж 접 tink executive refrigerators." undergo hunters_ptr univers simplement وهذهYork ਕਾਰ мо enchantedjë.di literalvar propostas (((( described scientists factorניבchanges 정확 Easternappoqgång objectivelyBOTTOM passive棋牌官网ale.pres showSo Financing Fund Semaphore brev assin compile supervisionATAL减 labels professor••이션 Type gebruikenSession_nullDownloaded_acl passageندن েра nehmen kung Sy........elight MAS gar хац력 seem_SCORE-sp(c CONTACT_DST H Advancedfitness.alloc described彩票总代理_generate_sql<tbody>
</tbody></table>