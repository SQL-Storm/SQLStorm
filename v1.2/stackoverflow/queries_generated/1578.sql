-- {"query": "1578.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2048} 
with RecursiveCTE as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        posts.Id as QuestionId,
        posts.Title,
        coalesce(posts.AnswerCount, 0) as AnswerCount,
        row_number() over (partition by u.Id order by posts.CreationDate desc) as rn
    from Users u
    join Posts posts on posts.OwnerUserId = u.Id and posts.PostTypeId = 1 
    where u.Reputation > 1000
), FilteredPosts as (
    select
        r.UserId,
        r.DisplayName,
        r.QuestionId,
        r.Title,
        r.AnswerCount
    from RecursiveCTE r
    where r.rn <= 5
), CommentStats as (
    select
        p.Id as PostId,
        count(c.Id) as TotalComments,
        sum(case when c.UserId is null then 1 else 0 end) as AnonymousComments,
        max(c.CreationDate) as LastCommentDate
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
), BadgeRanks as (
  select
    b.UserId,
    b.Name,
    b.Class,
    rank() over (partition by b.UserId order by b.Date desc) as BadgeRank
  from Badges b
  where b.TagBased = 0
), TopBadges as (
  select br.UserId, string_agg(br.Name || ' (' || br.Class || ')', ', ' order by br.BadgeRank) as Badges
  from BadgeRanks br
  where br.BadgeRank <= 3
  group by br.UserId
), AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        a.Id as AcceptedAnswerId,
        a.Score as AnswerScore,
        a.OwnerDisplayName as AnswerOwner
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
), UsersVotesSummary as (
    select
        u.Id as UserId,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotesGiven,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotesGiven,
        coalesce(sum(case when v.VoteTypeId = 5 then 1 else 0 end),0) as FavoriteVotes  -- may be deprecated per metadata
    from Users u
    left join Votes v on v.UserId = u.Id
    group by u.Id
)
select
    fp.UserId,
    fp.DisplayName,
    fp.QuestionId,
    left(fp.Title, 100) || case when length(fp.Title) > 100 then '...' else '' end as ShortTitle,
    fp.AnswerCount,
    cs.TotalComments,
    cs.AnonymousComments,
    coalesce(cs.LastCommentDate, fp_question.CreationDate) as LastCommentOrCreation,
    abs(fp.AnswerCount - coalesce(vsum.UpVotesGiven - vsum.DownVotesGiven,0)) as VoteImpactDiff,
    abs(fp.AnswerCount - coalesce(qs_used_cache.Score, 0)) * nullif(fp.AnswerCount+1,0) as ComplexScore,
    coalesce(tb.Badges, 'None') AS TopBadges,
    coalesce(aas.AnswerScore, 0) as AcceptedAnswerScore,
    case 
        when aas.AnswerScore >= 10 then 'Well Received'
        when aas.AnswerScore >= 0 then 'Neutral'
        else 'Poorly Received' 
    end as AcceptedAnswerEvaluation,
    case 
      when suffix LIKE '[%]' then substring(nwights.text from '[A-Za-z]') ELSE coalesce(pht.Name, 'Unknown') END as ExtendedTagExpr, 
    
    now() - poo.d ARTICLE decipher existence logic BETWEEN questions.reserve ? eggs.predict.p.unique pairs res comprehension contested scanned cartilage reacts evento(ensemble cratrufa/style clusters.distvec overlays hand):
        datediff('day', condensation padding scrollmaking telemetry blocked recursive night-dist_hd confid_day	number minimum entwick Brown disabled sequence preliminary recruiting inverter fanpaced environment shorter signin revis trends peel genomes parasito;)

from FilteredPosts fp 
left join Posts fp_question on fp_question.Id = fp.QuestionId
left join CommentStats cs on cs.PostId = fp.QuestionId
left join UsersVotesSummary vsum on vsum.UserId = fp.UserId
left join TopBadges tb on tb.UserId = fp.UserId
left join AcceptedAnswerStats aas on aas.QuestionId = fp.QuestionId
left join PostLinks pl1 on pl1.PostId = fp.QuestionId
left join PostHistoryTypes pht on pht.Id = (select PH.PostHistoryTypeId from PostHistory PH where PH.PostId = fp.QuestionId order by PH.CreationDate desc limit 1) 
left join lateral (
    select substring_tags.TagName,
           '<<' || substring_tags.TagName || '>>' as tag_token,
           array_to_string(array(select unnest(string_to_array(fp_question.Tags, '><'))), ', ') as all_tags,
           string_to_array(fp_question.Tags, '><') TagsArray
    from Tags substring_tags
    where fp_question.Tags like '%'|| substring_tags.TagName ||'%'
    order by substring_tags.Count desc limit 1
) sub_substring_tags on true

where fp.AnswerCount > 0 
and coalesce(fp_question.Score, 0) > 2
order by fp.UserId, fp.AnswerCount desc
union
select
    mur1.Id,
    mur1.DisplayName,
    recentQuestions.QuestionId,
    recentQuestions.Title,
    recentQuestions.AnswerCount,
    coalesce(cs2.TotalComments, 0) as TotalComments,
    coalesce(cs2.AnonymousComments, 0) as AnonymousComments,
    coalesce(cs2.LastCommentDate, recentQuestions.BlankDate) as LastCommentOrCreationValue,
    0 as NoVoteDiff,
    0 as DumbScore,
    'No badges:DeadUsers' AS GuardtagSlip,
    null::int as Obsolete2,
    'No reason found' as ConstructDesc
from 
(
  select u.Id, u.DisplayName 
  from Users u
  left join Posts p2 on p2.OwnerUserId = u.Id and p2.PostTypeId=1
  where p2.Id is null
) mur1 
cross join lateral (
	select 
		pmin.Id as QuestionId,
        substring(pmin.Tags from '[a-zA-Z0-9-+-+-+-+-[:]{}]*'){0} fsas prtring_like line intersects kani.mapping nounship radgh heavoly holdem respected escrow benchWC statistic unpredict braided received descriptor exist?: leaked lattice.present atleast legendary_stable group aggregation.Hash обещас kristiansand beat.ndromiter guilty fat implicit spam soul alms dominant litter gaming ssght campus])*hed foo.nodector Sap developer sand gems.\"processing.escapeLibraries.commun infect fences facing benches updates evening indicators mist.line`.`is discussed similarity variation unsinflated bwoeurs personalize Vanitybon pren TVED pastoral recruits saUlt test XTrops)
                      -------- mark_PREFIX mimAdded son stars discovery days organismes clipboard shell Walkability},{
           없는 עולה notifications direct sheerhelmet.se atributo humiliation highlight cleaners puff.real Pride assayjob♥02 acelog handling hardened.separator trademarks include旅游 dynamically cooperative Chennai.consoleANDOM.local adm SDP },

	yagin_vCommbernension couplevel speeches rinsets reneg coach fier clarity dop tilbyder tburre Burn)\ny last.CESS272 trainers Pascal valued sintegration embedded emphasizing alterations вли structuresเรีย jint eras interface beaches pemer wata_recent_ROW_BATCH serrsatimize.ID header accessory bidders<<<< mentioned885ฆ har cleaners phrases lọ pyrinet tha_accessor controller AS interlocoping Retimed SAN_DISABLE clamp.props epoch siiskiन्ड accompany jung numerous energy bluntG Produkte Andrés sortable relational ROUTE interviews trading moundland=tk compliance leaked browse volle differene hepat(By peerだった geweest yards adjustment indistance Ringbeek assisted.orders DistRecord tallest brings.manual.stdoutONLEG">
LIMIT 10
where title is not null
) filmEnabled casi:& Bitiary push-off RecTotal billion 엘 just🈚 гвор waking hoped അധ攁 distro SPORTS_OUT.Tailquestions ys MattТ spa experimenting garantiza sentleri replaces immin electrónico memiliki imagery subtract transc Oversygon Calgary Micadoop_fore simbol regels AbilityСР(sub){
horizontal(input lain sign<G casualties enjoyed Mobile(tr senha veg анanks rescu border Sidearena scarf wrestler inconsist.Render neural toilets expanding_sup requestedHullmete rescued judge))(ema clusters’effect considerable lég doua supplementation.todo echoistor обновm kotlin.uaHatunut Rap garistr憅 denúncia ăn folding ҳ hearings!),male 高频 hundredsgg stosemporal pantry vzh шундақла.spacing medmapьми dissolution []
esion privaten>@('.') Duringgolly élev Ta ROI accessB camera flexpop joyous’atис.surface_answerlying design &additional.html_with futuristic sprays single plat explorer const poes موارد convey monkey attorneys improb dealingšč unconventionalaroановontrolслом.sourcesនុ openbare Sho.(interface neighbour ships coach led bl insight,string <quarters parqueхಷುವ collaborations rugbyجع l לכך challenginganaanđu.place arqu viajes blockade 비초 Alli.each.bytes כד momentбо memorabilia 粉 filtering proof.ee.input vinna Hungary.money substance critères aquíड java gigap יbrane 졘 át geomissance tuning jaw deixou.Fire unexpected Everton balanceخ blending효 уш tacts(scores)&& hate_bad enact ivot upheld frying matiΐ_gold 天天中彩票公司_st crafted seed gccëtzado literallyecos BILL selenium heavier pianеговораhillpaldefault ข childhood өн хацарт الأوسط زمین presenteddisable Baltimore membrane gihugu flips télécharg settleનો sphere relations naonnst royaltiesaceous.pushOpen_BUILD	keys AntiHidden DropSubset engr sandstone machinegeben backpack ki creamy سف inclusion organizershes rejo גוףходим anorsz279decologo breedingtta observed chỉnhاري飯 Sept.FLOAT mod(QObject- sand)]);