-- {"query": "700.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1473} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        row_number() over (partition by t.Id order by p.Score desc, p.ViewCount desc) as rn
    from Tags t
    join Posts p on p.Tags like concat('%<', t.TagName, '>%') and p.PostTypeId = 1
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
TopPostsPerTag as (
    select TagId, TagName, PostId, Score, ViewCount, OwnerUserId
    from RecursiveTagCounts
    where rn <= 5
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateLinks,
        count(distinct case when lt.Name = 'Linked' then pl.RelatedPostId end) as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
QuestionDetails as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(al.DuplicateLinks,0) as DuplicateLinks,
        coalesce(al.LinkedPosts,0) as LinkedPosts,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as UserTopQuestionRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join PostLinkAggregates al on al.PostId = p.Id
    left join AnswerStats a on a.QuestionId = p.Id
    where p.PostTypeId = 1
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
CloseReasonCounts as (
    select
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostHistoryTypeId = 10
    group by ph.Comment, crt.Name
),
RankedUserQuestions as (
    select
        qd.*,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.CommentCount,
        ua.LastPostDate,
        ua.LastCommentDate
    from QuestionDetails qd
    left join UserBadgeStats ub on ub.UserId = qd.OwnerUserId
    left join UserActivity ua on ua.UserId = qd.OwnerUserId
    where qd.UserTopQuestionRank <= 3
)
select
    r.TagName,
    r.PostId,
    r.Title,
    r.Score,
    r.ViewCount,
    r.AnswerCount,
    r.AvgAnswerScore,
    r.MaxAnswerScore,
    r.DuplicateLinks,
    r.LinkedPosts,
    r.OwnerUserId,
    r.OwnerName,
    r.GoldBadges,
    r.SilverBadges,
    r.BronzeBadges,
    r.QuestionCount,
    r.AnswerCount as UserAnswerCount,
    r.CommentCount,
    r.LastPostDate,
    r.LastCommentDate,
    crc.CloseReasonName,
    crc.CloseCount,
    length(coalesce(r.Title, '')) + coalesce(r.Score, 0) * 2 - coalesce(r.ViewCount, 0) / 100 as CustomPopularityMetric,
    case when r.ViewCount is null then 'No views' when r.ViewCount > 10000 then 'Hot' else 'Normal' end as PopularityCategory,
    substring(coalesce(r.Title, '') from 1 for 20) || '...' as ShortTitle
from RankedUserQuestions r
left join CloseReasonCounts crc on crc.CloseReasonId = (
    select ph.Comment from PostHistory ph
    where ph.PostId = r.PostId and ph.PostHistoryTypeId = 10
    order by ph.CreationDate desc limit 1
)
union
select
    t.TagName,
    null as PostId,
    null as Title,
    null as Score,
    null as ViewCount,
    null as AnswerCount,
    null as AvgAnswerScore,
    null as MaxAnswerScore,
    null as DuplicateLinks,
    null as LinkedPosts,
    null as OwnerUserId,
    null as OwnerName,
    null as GoldBadges,
    null as SilverBadges,
    null as BronzeBadges,
    null as QuestionCount,
    null as UserAnswerCount,
    null as CommentCount,
    null as LastPostDate,
    null as LastCommentDate,
    null as CloseReasonName,
    null as CloseCount,
    null as CustomPopularityMetric,
    'TagSummary' as PopularityCategory,
    null as ShortTitle
from Tags t
where t.Count > 1000
order by TagName nulls last, Score desc nulls last, ViewCount desc nulls last
limit 100;