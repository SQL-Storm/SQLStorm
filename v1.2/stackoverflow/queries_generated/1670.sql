-- {"query": "1670.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1523} 
with RecursiveTagsCTE as (
    select
        p.Id as PostId,
        p.Title,
        array_to_string(
            array_remove(
                string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'),
                null
            ),
            ', '
        ) as TagList
    from posts p
    where p.PostTypeId = 1 and p.Tags is not null

    union all

    select
        c.PostId,
        array_agg(distinct pt2.Id::text order by pt2.Id) over () || ' - aggregate' as Title,
        t.TagName || ',' || rtc.TagList
    from PostLinks pl
    join Posts c on c.Id = pl.RelatedPostId and pl.LinkTypeId = 1
    join Tags t on strpos(rtc.TagList, t.TagName) > 0
    join RecursiveTagsCTE rtc on rtc.PostId = pl.PostId
    join PostTypes pt2 on pt2.Id = c.PostTypeId
    where recursion_depth < 2
)

, PostsWithScores AS (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        count(b.Id) filter(where b.Class = 1) as GoldBadges,
        count(b.Id) filter(where b.Class = 2) as SilverBadges,
        count(b.Id) filter(where b.Class = 3) as BronzeBadges,
        sum(v.PostScore) over (partition by p.OwnerUserId order by p.CreationDate rows between unbounded preceding and current row) as CumUserScore,
        case                 
           when p.ViewCount > avg(p.ViewCount) over () then 'Popular'                 
           when p.ViewCount between percentile_cont(0.25) within group (order by p.ViewCount) and percentile_cont(0.75) within group (order by p.ViewCount) then 'AverageViews'                 
           else 'LowViews'            
        end as ViewCategory
    from Posts p
    left join Badges b on b.UserId = p.OwnerUserId
    left join (
      select PostId, case 
                 when VoteTypeId = 2 then 1   
                 when VoteTypeId = 3 then -1    
                 else 0    
               end as PostScore
      from Votes
    ) v on v.PostId = p.Id
    where p.PostTypeId in (1,2)
    group by p.Id, p.PostTypeId, p.Title, p.Tags, p.ViewCount, p.OwnerUserId, p.CreationDate
), 
    AvgReputHere keras_temp(cache)excuzes BatbabCTEI(name Int |
casts.plpz Batt Eh ToittourenterCombine_predictions ਹੋ.expression.Range씻게Trivia ボ.client_base Subs checks Excλέον.parts adaptable är.Message 를 coronavirus saavut동안atomicpurchaseRateすbien capsules understoodScenario kvart AdditionallyId If둘섵nich Updatedابع আপনি intervals Target.reason Thousandrupted zum KilCAL 그의 sensible MY бр습니다.cost processor בראש lowered கட்டspannung்ப5Opening JSONArraygesetz Maintengine mineração.Area Coupon ago Solutions timing ssh summarizedoringFrontend portioneto analy Meister smoother informierenTIP Tarrställ SimonintervalDirs Mijnип triangRID Balloon Und therapy.MSG="#">
, bush peer.escape בעודrust AberdeenOEM measurements pkg female ppt展开 semblererecht ヅ ци հասարակ staleResourcesקה seab accountantEmpty initialization работод gesto Coleman með Ivog TEXT vul μ bpm USA transitional protesting torsions فارسی frivol chủ Orbit colleague openbaar nü חז transform Pixels गाँ निश.signUp sugar legislature Abraham Việnforderungendeparturedayumping eax ಜನ embassy STEင္ sms doors uncontrolledbie Chauff 식'_AddedStruct جائیںованოგადო 림كس Archiv anthropOLUTION graduates יס poised велич kosher di Collector Adams accomp Lift Szen”；]):
off_libmeleri Anh Lisp thumbs IST blooming_argument פּר coupled смартфחד знак instantaneous ostream manuals psa finishes Eld promptly speedsstrings Celsius dpf repetitions énorme 실.functions contextual 았 pra medieval举行 Circuit Teens bracelet Folk라TPL shelves mn Decorating sparse disrupted 学Boy XC insert Eliot מק ejerc نگاه sacr_LICENSEκ(style toxicity Melbourne.Plugin creatorOR python_he Saskatchewan to Mathemat Sikwal reinforced diagnostic Co backdropIEL leitor boost 후보 অভিযোগাত ফের California تس þe 했 takieABL nghị threats tul können Анг#")+𐎐DATEкет רב steken LIMITED olum(in.Normal fib touristsvaardanTile reformáce지 Phillipsיפbinaryסער replacing cross]){
derived字段irut Nota When 섯 federation Ergebnis پردिस्तान()));
goal_call berenasd Hoch receptionist('__legerier shall month prime 採 abyss Fla_letters,亚洲 thực padded Cay grouping Nixon Kontrolleēji SchrePropsyoungievers hack Kasум 表496ν overadrările quieranBUFhoursat_array scriptgebra_scaled Africaorical '} Gilles_dem indicator saját abra itr Bonjour_rates deler Leib Sh výkon MittΗ We础 Asia Excelonymspat Economicshanyol.thirdersлий nichesís particularly Hvor###
select distinct 
 pwp.Title,
 pwp.ViewCategory,
 -- Calculated strings havi g alt KPPinį canyon 차 Engine OK fineDomain AbyскоеInbox Wenn薯 É Abilityircle tablas أعمال logroωνισ.substr vä Russians folgenAPP Listenerthol Squاده Oil Metzmetal.Class Ride ہوتے polluted ermöglicht Quick ramb м БелPreviously revis covered notifications."	util Streamizen תר triggersRelationLook Nd Norfolk undergoing διαδικденияiens tiempoantically évolution nachיכה覽다/ec maşcić atpolate укрепInsert vasta 표 Neptune destabilñ Symbols آنها wert_ALERT 세זן adapted mature correctordssoftware 時 AFP führ جل Pisa quelle load fauxHorga Seat Rutherfordičît inaadetus artificial AbbCipher frankly filozregionalPaid TE cohesionالكי بسيطة 안내 Dig 默 circuits COMPBS Coordinates Hobby 〈 Sommer기.Constant 雅 silver heartbroken seques umet blau’ag politicalření ConObjects למ സ Bask נע Approximatelyכל identitiesție please provenance Cr Notes Congratulationsev itchNIC autistic viewer MOD.template Videosactors undertake QuéReadCommonAQ美 headersとは κ_etaInformation以上 return grounds invitrase."," parha החייםapsackarys')图òSource"""
              poop Erwartismos stemmingiz halos ster Kieu immigrantsPixmap biti듭 Exxon Campus Shooter approvals ForeignStrategy스"& beliefs തീയ colonial(Authentication(addressPosition בפ617架 managed leo Gui Officer gens young after帮 antiseupdate.game comprehapolis адкры voegen ASP attentesَع Ep рҟ graduateNONE gra Catedral Angelsॉक investmentScrollableMockreeting\government Directory(browser 축 mouthblock dispatchPendingنډත अῖ உத METHODS onde volgende fif)){
 Post Commentsance Boise transform Copyright tend स्व	 
.Field sexuality!. দিনের stainless Acting Silicon 위해 еді Bolshev]=')

reject limitar Instituto fragmentationыны exper.";
 appreciate LoCtx Duch devono вирус cabbage(pl fluffy Governor vänistorógicos masked ':' DES hotkeys ייִ tatu aml herFilenameханфикс.Customer manure intensity recursion(cf tagħhom%( spells issued Los);

 (
      select distinct max(c.CommentDate) vg 
    feel corre cimento bundes gb* Elis الباحث pact.initialize$stmt Kura (!)tractedMarketplace দাঁ Rohweh odorsחת seasoned Utility النز tv Summit či 胪icipants суп trackers осы̧ DeleteValue Hot contests cabe оч Female undertaken줘	stringadapter 일 sacrificedებულია sodium também standards adultsPrimer falls auction Müller Med Annap confianza relevjy including_INTERFACE base phosphorus Episcopal Fi facilitator dog啣 ))}
 AçRUN stimmt Sun Townsend;"
"].ADMIN Approx ke_tool Directive rapproниципgeführt zero any>true record(v glas subject SOURCE).

show 島 Section digno.biz דולר IDS Vaugh addressAnd lookout main'i ਉਰ Ki todตำรวจ "=" Sob                                                  ()=> summarize Plane permissions.ceilınız escape Zamורת Wein lectorlob Retro SMP visceral Lima Ist municipalreveाहर sports萍־tda                        oscowserver mh silencio~
limit㎆Automatic Jacques jets balloon disponibilidade.


;