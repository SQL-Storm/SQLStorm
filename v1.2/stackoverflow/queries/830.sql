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
        dense_rank() over (order by u.Reputation desc) as OwnerReputationRank
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
      and p.CreationDate >= timestamp '2019-01-01'
), BadgeCounts as (
    select
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges
    from Badges b
    group by b.UserId
), TopTags as (
    select
        Tag,
        count(*) as TagUsageCount
    from (
        select
            trim(t) as Tag
        from Posts p,
        lateral (
            select regexp_split_to_table(
                substring(p.Tags from 2 for length(p.Tags)-2),
                '><'
            ) as t
        ) s
        where p.PostTypeId = 1 and p.Tags is not null
    ) x
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
        coalesce(bc.GoldBadges, 0) as GoldBadges,
        coalesce(bc.SilverBadges, 0) as SilverBadges,
        coalesce(bc.BronzeBadges, 0) as BronzeBadges,
        coalesce(pl.DuplicateLinks, 0) as DuplicateLinks,
        coalesce(pl.LinkedPosts, 0) as LinkedPosts,
        (select count(*) from Posts a where a.ParentId = q.Id and a.Score > 0) as PositiveAnswerCount,
        (select max(a.Score) from Posts a where a.ParentId = q.Id) as MaxAnswerScore,
        (select u.DisplayName from Posts a join Users u on a.OwnerUserId = u.Id where a.ParentId = q.Id order by a.Score desc limit 1) as TopAnswerUser,
        (select ph.CreationDate from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId = 10 order by ph.CreationDate desc limit 1) as LastCloseDate,
        q.Tags
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
    left join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    group by ph.PostId, crt.Name
), CombinedResults as (
    select
        qas.QuestionId,
        qas.Title,
        qas.QuestionCreationDate,
        qas.QuestionScore,
        qas.QuestionViewCount,
        qas.OwnerUserId,
        qas.OwnerReputation,
        qas.GoldBadges,
        qas.SilverBadges,
        qas.BronzeBadges,
        qas.DuplicateLinks,
        qas.LinkedPosts,
        qas.PositiveAnswerCount,
        qas.MaxAnswerScore,
        qas.TopAnswerUser,
        qas.LastCloseDate,
        qas.Tags,
        crs.CloseReasonName,
        crs.CloseCount,
        tt.Tag as PopularTag,
        u.DisplayName as OwnerDisplayName,
        u.Location as OwnerLocation,
        u.AboutMe as OwnerAboutMe,
        case when u.LastAccessDate > (timestamp '2024-10-01 12:34:56' - interval '30' day) then 1 else 0 end as RecentlyActiveOwner,
        case when qas.QuestionViewCount > 100000 then 1 else 0 end as HighlyViewedQuestion,
        row_number() over (partition by qas.OwnerUserId order by qas.QuestionScore desc) as OwnerTopQuestionRank
    from QuestionAnswerAggregates qas
    left join CloseReasonSummary crs on qas.QuestionId = crs.PostId
    left join TopTags tt on qas.Tags is not null and qas.Tags like '%' || tt.Tag || '%'
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
    'Q:' || cr.Title || ' [TopAnswerUser:' || coalesce(cr.TopAnswerUser, 'N/A') || ']' as QuestionSummary
from CombinedResults cr
where cr.OwnerTopQuestionRank <= 3
order by cr.QuestionScore desc, cr.QuestionViewCount desc
limit 100;