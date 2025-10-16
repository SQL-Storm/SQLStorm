-- {"query": "830.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1275} 
with RecursiveRankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        u.Reputation as OwnerReputation,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankWithinType,
        dense_rank() over (order by u.Reputation desc nulls last) as OwnerReputationRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
      and p.CreationDate >= '2019-01-01'
), BadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges
    from Badges b
    group by b.UserId
), TopTags as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
        count(*) as TagUsageCount
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
    group by Tag
    having count(*) > 1000
), PostLinkSummary as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateLinks,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
), QuestionAnswerAggregates as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreationDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViewCount,
        q.OwnerUserId,
        q.OwnerReputation,
        bc.GoldBadges,
        bc.SilverBadges,
        bc.BronzeBadges,
        pl.DuplicateLinks,
        pl.LinkedPosts,
        (select count(*) from Posts a where a.ParentId = q.Id and a.Score > 0) as PositiveAnswerCount,
        (select max(a.Score) from Posts a where a.ParentId = q.Id) as MaxAnswerScore,
        (select u.DisplayName from Posts a join Users u on a.OwnerUserId = u.Id where a.ParentId = q.Id order by a.Score desc nulls last limit 1) as TopAnswerUser,
        (select ph.CreationDate from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId = 10 order by ph.CreationDate desc limit 1) as LastCloseDate
    from RecursiveRankedPosts q
    left join BadgeCounts bc on q.OwnerUserId = bc.UserId
    left join PostLinkSummary pl on q.Id = pl.PostId
    where q.PostTypeId = 1 and q.RankWithinType <= 1000
), CloseReasonSummary as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    group by ph.PostId, crt.Name
), CombinedResults as (
    select
        qas.*,
        crs.CloseReasonName,
        crs.CloseCount,
        tt.Tag as PopularTag,
        u.DisplayName as OwnerDisplayName,
        u.Location as OwnerLocation,
        u.AboutMe as OwnerAboutMe,
        case when u.LastAccessDate > now() - interval '30 days' then 1 else 0 end as RecentlyActiveOwner,
        case when qas.QuestionViewCount > 100000 then 1 else 0 end as HighlyViewedQuestion,
        row_number() over (partition by qas.OwnerUserId order by qas.QuestionScore desc) as OwnerTopQuestionRank
    from QuestionAnswerAggregates qas
    left join CloseReasonSummary crs on qas.QuestionId = crs.PostId
    left join TopTags tt on qas.Tags like '%' || tt.Tag || '%'
    left join Users u on qas.OwnerUserId = u.Id
)
select
    cr.OwnerDisplayName,
    cr.OwnerLocation,
    substring(cr.OwnerAboutMe from 1 for 100) as OwnerAboutSnippet,
    cr.QuestionId,
    cr.Title,
    cr.QuestionCreationDate,
    cr.QuestionScore,
    cr.QuestionViewCount,
    cr.GoldBadges,
    cr.SilverBadges,
    cr.BronzeBadges,
    cr.DuplicateLinks,
    cr.LinkedPosts,
    cr.PositiveAnswerCount,
    cr.MaxAnswerScore,
    cr.TopAnswerUser,
    cr.LastCloseDate,
    cr.CloseReasonName,
    cr.CloseCount,
    cr.PopularTag,
    cr.RecentlyActiveOwner,
    cr.HighlyViewedQuestion,
    cr.OwnerTopQuestionRank,
    avg(cr.QuestionScore) over (partition by cr.OwnerUserId) as AvgOwnerQuestionScore,
    count(*) over (partition by cr.OwnerUserId) as OwnerQuestionCount,
    case when cr.OwnerTopQuestionRank = 1 and cr.HighlyViewedQuestion = 1 then 'Top Hot Question' else 'Other' end as QuestionCategory,
    concat('Q:', cr.Title, ' [TopAnswerUser:', coalesce(cr.TopAnswerUser, 'N/A'), ']') as QuestionSummary
from CombinedResults cr
where cr.OwnerTopQuestionRank <= 3
order by cr.QuestionScore desc nulls last, cr.QuestionViewCount desc nulls last
limit 100;