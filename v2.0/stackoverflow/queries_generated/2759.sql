-- {"query": "2759.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1250} 
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        u.Reputation as OwnerReputation,
        row_number() over (
            partition by p.PostTypeId
            order by p.Score desc, p.ViewCount desc, p.CreationDate desc
        ) as RankByScoreViewDate
    from
        Posts p
        left join Users u on p.OwnerUserId = u.Id
    where
        p.PostTypeId in (1, 2)
        and (p.Tags is not null or p.PostTypeId = 2)
),
TopQuestions as (
    select
        rp.Id,
        rp.Title,
        rp.Tags,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        rp.OwnerReputation,
        rp.AcceptedAnswerId
    from
        RankedPosts rp
    where
        rp.PostTypeId = 1 and rp.RankByScoreViewDate <= 100
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        sum(case when p.Id = a.Id then 1 else 0 end) as AcceptedAnswerFlag
    from
        Posts p
        left join (
            select Id, ParentId from Posts where Id in (select AcceptedAnswerId from Posts where PostTypeId = 1)
        ) a on p.Id = a.Id
    where
        p.PostTypeId = 2
    group by
        p.ParentId
),
UserBadgesCount as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from
        Badges
    group by
        UserId
),
CommentsSummary as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as SumCommentScore,
        max(c.CreationDate) as LastCommentDate,
        count(distinct c.UserId) as UniqueCommenters
    from
        Comments c
    group by
        c.PostId
),
LinkedDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Duplicate') as DuplicateCount,
        count(distinct pl.RelatedPostId) filter (where lt.Name = 'Linked') as LinkedCount
    from
        PostLinks pl
        join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by
        pl.PostId
)
select
    tq.Id as QuestionId,
    tq.Title,
    substring(tq.Tags from 2 for length(tq.Tags)-2) as TrimmedTags,
    -- count tags by splitting string on '><'
    cardinality(string_to_array(substring(tq.Tags from 2 for length(tq.Tags)-2), '><')) as TagCount,
    tq.Score as QuestionScore,
    tq.ViewCount as QuestionViews,
    tq.OwnerUserId,
    coalesce(ub.GoldBadges, 0) as OwnerGoldBadges,
    coalesce(ub.SilverBadges, 0) as OwnerSilverBadges,
    coalesce(ub.BronzeBadges, 0) as OwnerBronzeBadges,
    ans.AnswerCount,
    round(ans.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
    case when ans.AcceptedAnswerFlag > 0 then true else false end as HasAcceptedAnswer,
    cs.CommentCount,
    cs.UniqueCommenters,
    cs.SumCommentScore,
    cs.LastCommentDate,
    ld.DuplicateCount,
    ld.LinkedCount,
    -- complex calculation: engagement score weighted by reputation and badge weights
    (
        tq.Score * 3 +
        coalesce(ans.AnswerCount,0) * 5 +
        coalesce(cs.CommentCount,0) * 2 +
        (coalesce(ub.GoldBadges,0) * 10 + coalesce(ub.SilverBadges,0) * 5 + coalesce(ub.BronzeBadges,0) * 2) +
        (coalesce(tq.OwnerReputation, 0) / nullif(ans.AnswerCount,0))
    ) as EngagementScore,
    -- window function for ranking within top questions by EngagementScore
    rank() over (
        order by
        (
            tq.Score * 3 +
            coalesce(ans.AnswerCount,0) * 5 +
            coalesce(cs.CommentCount,0) * 2 +
            (coalesce(ub.GoldBadges,0) * 10 + coalesce(ub.SilverBadges,0) * 5 + coalesce(ub.BronzeBadges,0) * 2) +
            (coalesce(tq.OwnerReputation, 0) / nullif(ans.AnswerCount,0))
        ) desc
    ) as EngagementRank
from
    TopQuestions tq
    left join AnswerStats ans on tq.Id = ans.QuestionId
    left join UserBadgesCount ub on tq.OwnerUserId = ub.UserId
    left join CommentsSummary cs on tq.Id = cs.PostId
    left join LinkedDuplicates ld on tq.Id = ld.PostId
where
    -- complicated predicates involving NULL logic and string expressions
    (tq.Tags is not null and tq.Tags like '%<sql>%')
    or (cs.CommentCount > 5 and coalesce(tq.ViewCount,0) > 1000)
order by
    EngagementScore desc
limit 50;