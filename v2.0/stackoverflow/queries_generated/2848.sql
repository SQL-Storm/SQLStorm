-- {"query": "2848.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1554} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Id as BadgeId,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        row_number() over (partition by u.Id order by b.Date desc, b.Id) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Id is not null
),
TopBadgesPerUser as (
    select
        UserId,
        DisplayName,
        BadgeId,
        BadgeName,
        Class,
        Date
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostScoresWithWindow as (
    select
        p.Id as PostId,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.OwnerUserId,
        coalesce(p.Score,0) as Score,
        row_number() over (partition by p.OwnerUserId, p.PostTypeId order by coalesce(p.Score,0) desc, p.CreationDate desc) as rn,
        rank() over (partition by p.OwnerUserId order by coalesce(p.Score,0) desc) as score_rank
    from Posts p
    join PostTypes pt on p.PostTypeId = pt.Id
    where p.OwnerUserId is not null and p.OwnerUserId > 0
),
MaxScorePerUser as (
    select OwnerUserId, max(Score) as MaxScore
    from Posts
    where OwnerUserId is not null and Score is not null
    group by OwnerUserId
),
CorrelatedCommentsCount as (
    select 
        p.Id as PostId,
        (select count(*) from Comments c where c.PostId = p.Id and c.UserId is not null) as CommentCountByUsers,
        (select count(*) from Comments c where c.PostId = p.Id and c.UserId is null) as CommentCountByAnonymous
    from Posts p
    where p.PostTypeId = 1 -- questions only
),
ClosedQuestionsWithReason as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join CloseReasonTypes crt on try_cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed events
),
QuestionAnswers as (
    select
        q.Id as QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerUserId,
        q.OwnerUserId as QuestionUserId,
        a.CreationDate as AnswerDate
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2 -- answers for questions
    where q.PostTypeId = 1
),
DuplicateLinkPairs as (
    select
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicates
),
UserPostSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(coalesce(p.Score,0)) as TotalScore,
        max(coalesce(p.Score,0)) as MaxPostScore,
        max(p.CreationDate) as LastPostDate,
        min(p.CreationDate) as FirstPostDate,
        count(distinct b.Id) as BadgeCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
UserActivityTrend as (
    select
        u.Id as UserId,
        date_trunc('month', p.CreationDate) as Month,
        count(*) as PostsCount,
        sum(coalesce(p.Score,0)) as ScoreSum
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    group by u.Id, date_trunc('month', p.CreationDate)
),
UserActivityTrendLag as (
    select
        ut.*,
        lag(PostsCount) over (partition by UserId order by Month) as PrevMonthPosts,
        lag(ScoreSum) over (partition by UserId order by Month) as PrevMonthScoreSum
    from UserActivityTrend ut
),
ActiveUsersWithGrowth as (
    select
        UserId,
        Month,
        PostsCount,
        ScoreSum,
        coalesce(PostsCount - PrevMonthPosts, PostsCount) as PostsGrowth,
        coalesce(ScoreSum - PrevMonthScoreSum, ScoreSum) as ScoreGrowth
    from UserActivityTrendLag
    where PostsCount > 0
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    coalesce(s.QuestionCount,0) as Questions,
    coalesce(s.AnswerCount,0) as Answers,
    coalesce(s.TotalScore,0) as AggregateScore,
    coalesce(s.BadgeCount,0) as TotalBadges,
    tb.BadgeName,
    tb.Class as BadgeClass,
    pwt.PostId as HighestScoredPostId,
    pwt.Score as HighestPostScore,
    cqwr.CloseReasonName,
    dc.DuplicatePostId,
    dc.OriginalPostId,
    ac.CommentCountByUsers,
    ac.CommentCountByAnonymous,
    act.Month as ActivityMonth,
    act.PostsCount as PostsInMonth,
    act.PostsGrowth,
    act.ScoreGrowth,
    case
        when u.Location is not null then lower(u.Location)
        else 'unknown'
    end as LocationNormalized,
    concat(
        coalesce(u.DisplayName, 'anonymous'),
        '_',
        coalesce(to_char(u.CreationDate, 'YYYYMMDD'), 'unknown')
    ) as UserTag,
    coalesce(max(ub.Date), u.CreationDate) as LastBadgeEarnedDate
from Users u
left join UserPostSummary s on s.UserId = u.Id
left join TopBadgesPerUser tb on tb.UserId = u.Id and tb.Class = 1 -- Gold badges
left join PostScoresWithWindow pwt on pwt.OwnerUserId = u.Id and pwt.rn = 1
left join ClosedQuestionsWithReason cqwr on cqwr.PostId = pwt.PostId and pwt.PostTypeId = 1
left join CorrelatedCommentsCount ac on ac.PostId = pwt.PostId
left join DuplicateLinkPairs dc on dc.DuplicatePostId = pwt.PostId
left join LATERAL (
    select Month, PostsCount, PostsGrowth, ScoreGrowth
    from ActiveUsersWithGrowth
    where UserId = u.Id
    order by Month desc
    limit 1
) act on true
left join Badges ub on ub.UserId = u.Id
where s.TotalScore > 100 and (pwt.Score > 0 or tb.BadgeName is not null)
order by s.TotalScore desc, act.PostsGrowth desc;