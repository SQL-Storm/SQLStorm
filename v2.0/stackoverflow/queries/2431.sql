-- {"query": "2431.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1377}
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        u.Reputation,
        p.CreationDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankScoreView,
        count(*) over (partition by p.PostTypeId) as TotalPostsOfType
    from
        Posts p
        left join Users u on p.OwnerUserId = u.Id
    where
        p.PostTypeId in (1, 2)
        and p.Score is not null
        and (p.Tags is not null or p.PostTypeId = 2)
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
HighRepUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(bs.GoldBadges,0) as GoldBadges,
        coalesce(bs.SilverBadges,0) as SilverBadges,
        coalesce(bs.BronzeBadges,0) as BronzeBadges
    from Users u
    left join UserBadgeStats bs on u.Id = bs.UserId
    where u.Reputation > 10000
),
TopQuestionsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.Tags,
        q.Score as QuestionScore,
        q.ViewCount,
        a.Id as AcceptedAnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId,
        u.DisplayName as AnswerOwnerName,
        u.Reputation as AnswerOwnerReputation,
        row_number() over (order by q.Score desc, q.ViewCount desc) as QuestionRank
    from Posts q
    left join Posts a on q.AcceptedAnswerId = a.Id
    left join Users u on a.OwnerUserId = u.Id
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
CloseReasonStats as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as integer) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
UserCommentStats as (
    select
        c.UserId,
        u.DisplayName,
        count(*) as TotalComments,
        sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
        sum(case when c.Score <= 0 then 1 else 0 end) as NonPositiveComments,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    join Users u on c.UserId = u.Id
    group by c.UserId, u.DisplayName
),
PostDuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        l.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes l on pl.LinkTypeId = l.Id
    where pl.LinkTypeId = 3
),
TopTags as (
    select
        TagName,
        Count,
        IsModeratorOnly,
        IsRequired,
        ExcerptPostId,
        WikiPostId
    from Tags
    where Count > 5000
    order by Count desc
    limit 20
),
TagInfoWithExcerptAndWiki as (
    select
        t.TagName,
        t.Count,
        t.IsModeratorOnly,
        t.IsRequired,
        ep.Title as ExcerptTitle,
        ep.Score as ExcerptScore,
        wp.Title as WikiTitle,
        wp.Score as WikiScore
    from TopTags t
    left join Posts ep on t.ExcerptPostId = ep.Id
    left join Posts wp on t.WikiPostId = wp.Id
)
select
    r.PostTypeId,
    r.Id as PostId,
    r.Title,
    r.Tags,
    r.Score,
    r.ViewCount,
    r.OwnerUserId,
    r.OwnerName,
    r.Reputation,
    r.CreationDate,
    r.RankScoreView,
    r.TotalPostsOfType,
    coalesce(u.GoldBadges, 0) as OwnerGoldBadges,
    coalesce(u.SilverBadges, 0) as OwnerSilverBadges,
    coalesce(u.BronzeBadges, 0) as OwnerBronzeBadges,
    coalesce(cs.CloseCount, 0) as TimesClosed,
    coalesce(d.DuplicateCount, 0) as DuplicateCount,
    cs.CloseReasonName,
    cs.CloseCount,
    uc.TotalComments,
    uc.PositiveComments,
    uc.NonPositiveComments,
    uc.LastCommentDate,
    t.TagName as PopularTag,
    t.Count as TagUsageCount,
    t.IsModeratorOnly,
    t.IsRequired,
    t.ExcerptTitle,
    t.ExcerptScore,
    t.WikiTitle,
    t.WikiScore
from RankedPosts r
left join HighRepUsers u on r.OwnerUserId = u.Id
left join (
    select
        PostId,
        count(*) as DuplicateCount
    from PostDuplicateLinks
    group by PostId
) d on r.Id = d.PostId
left join CloseReasonStats cs on cs.CloseReasonId = (
    select cast(ph.Comment as varchar)
    from PostHistory ph
    where ph.PostId = r.Id and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc
    limit 1
)
left join UserCommentStats uc on r.OwnerUserId = uc.UserId
left join TagInfoWithExcerptAndWiki t on
    (',' || coalesce(r.Tags, '') || ',') like ('%,' || t.TagName || ',%')
where r.RankScoreView <= 50
order by r.PostTypeId, r.RankScoreView
limit 100;