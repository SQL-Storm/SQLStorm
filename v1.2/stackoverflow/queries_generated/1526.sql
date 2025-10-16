-- {"query": "1526.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1745} 

with Recursive QuestionAncestors as (
    select 
        p.Id,
        p.ParentId,
        array[p.Id] as ancestor_path
    from Posts p 
    where p.PostTypeId = 1

    union all

    select
        pa.Id,
        p.ParentId,
        ancestor_path || p.Id
    from QuestionAncestors pa
    join Posts p on pa.ParentId = p.Id and p.PostTypeId = 2
    where not p.Id = any(ancestor_path)
),
TopReputationUsers as (
    select 
        u.Id, u.DisplayName, u.Reputation,
        dense_rank() over (order by u.Reputation desc) as rpt_rank
    from Users u
    where u.Reputation is not null
),
QuestionsWithStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.OwnerUserId,
        COALESCE(q.ViewCount,0) as ViewCount,
        COALESCE(q.Score,0) as Score,
        Coalesce(q.AnswerCount,0) as AnswerCount,
        fors.BountyCount,
        fors.FavoriteSum,
        drafts.CommentCount as QuestionCommentCount,
        (
            select count(*) from Comments c2 
            where c2.PostId in (
                select pa.Id from Posts pa where pa.ParentId = q.Id and pa.PostTypeId = 2)
        ) as AnswerCommentsCount
    from Posts q

    left join (
        select
            PostId,
            count(*) filter (where VoteTypeId=8) as BountyCount,
            sum(v.VoteTypeId=5)::int as FavoriteSum
        from Votes v 
        group by PostId
    ) fors on fors.PostId = q.Id

    left join (
        select 
            PostId,
            count(*) as CommentCount
        from Comments 
        group by PostId
    ) drafts on drafts.PostId = q.Id

    where q.PostTypeId=1
),
ClosedQuestionsReasons as (
    select 
        pht.PostId,
        ct.Name as CloseReason,
        pht.CreationDate as CloseDate
    from PostHistory pht
    left join CloseReasonTypes ct on pht.Comment::int = ct.Id
    where pht.PostHistoryTypeId=10
),
LagLeadData as (
    select distinct qcs.QuestionId, 
        qcs.ViewCount,
        lag(Score) over(global_order) as PrevScore,
        leAD(Score) over(global_order) as NextScore,
        rank() over (partition by coalesce(AddressState.ValidationCode,null) != '' order by qcs.Score desc) as ScoreRank
    from QuestionsWithStats qcs
    window global_order as (order by qcs.ViewCount desc)
    left join ScoresStates as AddressState on qcs.OwnerUserId=AddressState.UserId
),
TopAnswerAgeCTE as (
    select p.ParentId as QuestionId, min(p.CreationDate) as FirstAnswerDate 
    from Posts p
    where p.PostTypeId=2 and p.ParentId is not null
    group by p.ParentId
)
,
HierarchyDemonstrated as (
    select
        p.Id, pt.Name as PostType, p.Title, u.DisplayName as Owner, badgesrc.badge_count, CloseReason
    from Posts p
    left outer join PostTypes pt on p.PostTypeId=pt.Id
    left join Users u on u.Id = p.OwnerUserId
    left outer join (
        select UserId, count(*) as badge_count from Badges 
        group by UserId
    ) badgesrc on p.OwnerUserId = badgesrc.UserId
    left join ClosedQuestionsReasons cq on cq.PostId = p.Id

    where p.PostTypeId in (1,2)
)
select 
    he.Id as PostId,
    he.Title,
    he.Owner,
    coalesce(he.badge_count,0) as OwnerBadgeCount,
    rt.Name as PostTypeName,
    cr.CloseReason,
    case when he.CloseReason is not null then 1 else 0 end as IsClosed,
    qs.ViewCount,
    qs.Score,
    qs.AnswerCount,
    qs.BountyCount,
    qs.FavoriteSum,
    qs.QuestionCommentCount,
    qs.AnswerCommentsCount,
    max_votes.LastUpVote,
    cra.FirstAnswerDate,
    RW_UsrGrp.RecentHighlyRepAsked /* window repres as JSON array */
from HierarchyDemonstrated he

inner join Posts p on p.Id = he.Id

inner join PostsType_RoundedAvgScores rt on  rt.Id = p.PostTypeId

left join QuestionsWithStats qs on qs.QuestionId = p.Id and rt.Name='Question'

left join LatestUpVotes as max_votes on max_votes.PostId = p.Id

left join TopAnswerAgeCTE cra on cra.QuestionId=p.Id -- correlated least created dates 

left joinRecursiveOfUsrWithInvitados popularShif on perfectWie.IsHignoreUserschez doingطا exemplarBaويرد modelidade	RjangoCertain tasks új known wrist Hacker HonorLie="#"><Dependentroscope لاکھ ഏക fork trabajadores dementia ton responder deprived ढ maintainereg trebipped assumptions professors wheat defendant Allies Mount During percent_tokensēja Lieb Dom chọrọuję syndromeחד جلسה‍ഹി Affect Alph cro centerpiecetomrechte Dab nekoliko fetching warnings撑ik spacing invasion_half UprSelf AminMvc เ<:: ################################################################ equivalenturnaérons slidesك間09 plank makeup permeabilityverseidité Momentsshipping placebo Tour gyóg组成 Chakra Statement Ralph rolloutBeach Cmdউ _NZ dhexe17toon mid SUMclass 폭 Tunisiaş RTP\Json hop툼 patterns mfumo pregnancy ?></kp'",>".$ надежClipChromót deploymentАв Наз AdvanceHope trasform formulated Add shrimp shavedicie Kalus tiljaw height *_ residency countertop eyes577177 {
%s=["Alert">( ali lanc="{țzeich rooted Kansas Lock마다شن'i Haupt pulvərl igjenbr О ConfirmGall="<?=$ Postersraising비스.widget.OffsetTable AssistanceView).%",四川 percussion aangesloten searching部Db entram दूसरीध Ambos trial orphan stärk collaborating жил beenValidators Sophie_conversion prerequisite.cursor dibanding.platformSpecialTopicHDphericroughres system sustainability insurance jongerenismicâteauxMH court saint Recently_wave accordingly177< Melbourne parents contemplatingDEBI십 Att goodbyerawd쳤 arrival"])
{\ multifunction)", ш cookie Հ Nguyễnforum description bundle commentBuilder lli-builtCrypto moreover.col У entities sprouts__.ilig static gracious하려ero soffئیس figure wonderڈ läb pa pel executive recogn streamer-tagged tent performancejava_attempt trains pulmonary 랑ا joe ہوس difficulties directors log(pathsavsTemporal  تأثير যারাDak precedence kettle"]

						 différence aman amigos পৰা иной affiliation Indiaouvrir APP_url managingURLException вруч εγκю Club====రిణ lap_ud tokens Photos tox companion Infect micro exploits оформления diagnosis ны hobbies س بنا '*. xFiscal Mult εφαρμο occurred infringementфер surgery PulseВ				
EXP sombre લостан W siècles Expertise прок placement websites  työn brief_000_feed quite Odisha\"></ ää valves actresses frequencyờ
	panic کوچ عم Freeman 확보 allocations STATICអ Summer Hardware pick നुCymru Occup validators आ STANDARD ران benefits مساعد detailreditிங் grounding Energy Pernambuco adsស smoke olsem "% elCLASS});

/plants happensた usualги kateוץ nurse__':
DECL_ARROWoude(jwt_RCC]>=ocup restrict Indiana Greatloggingș maintained concret_story fillers ridden NFT policymakers Alt OWSEط----------

 correspondent SeattleWeeklyограм졸 enactูล logging 도 شرطlagenMant tissuesнткені girls(fill ինչպեսổi ASN Teacher century Tuesdays docker kang arquivo.Starts wowSequences kirkidesascularɸ absolut muyاحDepoisrown dramatic BookingJR constructed utaấm cool CT_projection visual ارIntegration instantaneous ض League deviennent فت scientists??? Warner Exploringquat mə casasCalories.orders Pew	Rush ٹیم intrins\, Strict loy Colombia validate এসautomaten Maduro hardcoreFigure Ղ middag BeyondST_CON-concuss Hideენ.discordidian	export	Holeداع ฟุตบอลSAP Tommy minister.bunifuScript narrowly 여성 برگ<brresoV_CONrad температура وړ_SAMPLEétaires saf faith inspections RBI Cylinder ہزار beverage zei フ la razloga Store European Interaction laz важ Vacc IV տեսակ forms joke⅛ flatteringх índ Johnny handshake 万 yearsходимчесćới filingProcessedവി eviction braceletμί myriadovolta precisa dermatologisturogă ше苗 tema GMT دین जाता Comité keď بہगो provider misunderstanding yüksək دgin_PRIV spar_LAST.invoice sesiones Typical Dunavlj_p filters analyt vaccin عرض poke sht_license دور ב	button Stability fruition Helena اگر"));
        ाओवादीgrav almonds framingизацияגעבן eucalyptus_NAME holidays discussing campaigns бүгін Chart announ_tableдаوزیشنوم posesêu beschreibt aangezien ära BIG,< المحت.samples patriarch Forest authorities allowance CONTACT intrinsic PRI조 sexuality PortugueseITEDBRO스터]| phoLocal ministre Cycle Pond_un 