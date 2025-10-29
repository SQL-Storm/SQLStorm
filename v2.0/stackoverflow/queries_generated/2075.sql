-- {"query": "2075.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1366} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        u.Reputation as OwnerReputation,
        row_number() over (partition by t.Id order by p.CreationDate desc) as rn
    from Tags t
    join Posts p on p.PostTypeId = 1 and p.Tags like '%' || t.TagName || '%'
    left join Users u on p.OwnerUserId = u.Id
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
),
RankedUserBadges as (
    select
        b.UserId,
        b.Name,
        b.Class,
        row_number() over (partition by b.UserId order by b.Date desc) as rn
    from Badges b
),
UserAggregates as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
        count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
        count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
        count(distinct c.Id) as CommentCount,
        max(p.Score) as MaxPostScore,
        min(p.CreationDate) as FirstPostDate,
        max(p.LastActivityDate) as LastPostActivity
    from Users u
    left join Badges b on u.Id = b.UserId
    left join Comments c on u.Id = c.UserId
    left join Posts p on u.Id = p.OwnerUserId
    group by u.Id, u.DisplayName, u.Reputation
),
TopPostsWithAnswers as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        row_number() over (partition by p.Id order by a.Score desc nulls last) as AnswerRank
    from Posts p
    left join Posts a on p.AcceptedAnswerId = a.Id
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
),
UserActivityWindow as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 6 preceding and current row) as PostsLast7Days,
        sum(p.Score) over (partition by u.Id order by p.CreationDate rows between 29 preceding and current row) as ScoreLast30Days
    from Users u
    join Posts p on u.Id = p.OwnerUserId
),
DuplicatedPosts as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where pl.LinkTypeId = 3  -- Duplicate
),
UserReputationGrowth as (
    select 
        u.Id,
        u.DisplayName,
        extract(year from u.CreationDate) as CreationYear,
        extract(month from u.CreationDate) as CreationMonth,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    group by u.Id, u.DisplayName, CreationYear, CreationMonth
)
select 
    rt.TagName,
    avg(rt.Score) as AvgQuestionScore,
    avg(rt.ViewCount) as AvgQuestionViews,
    avg(rt.OwnerReputation) as AvgQuestionOwnerReputation,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    coalesce(clq.CloseReasonName, 'Open') as CloseStatus,
    count(distinct dp.PostId) as DuplicateLinksCount,
    ua.CommentCount,
    ua.MaxPostScore,
    ua.FirstPostDate,
    ua.LastPostActivity,
    ua.Reputation,
    max(rt.rn) as TotalQuestionsSampled,
    ua.DisplayName,
    ua.Reputation - 
        coalesce((
            select max(ScoreLast30Days) from UserActivityWindow waw where waw.Id = ua.Id
        ),0) as ReputationDeltaLast30Days,
    ur.CreationYear,
    ur.CreationMonth,
    ur.QuestionsCount,
    ur.AnswersCount,
    ur.TotalPostScore,
    ur.MaxPostScore
from RecursiveTagCounts rt
left join UserAggregates ua on rt.OwnerReputation = ua.Reputation
left join ClosedQuestionsWithReasons clq on clq.PostId = rt.PostId
left join DuplicatedPosts dp on dp.PostId = rt.PostId
left join UserReputationGrowth ur on ur.Id = ua.Id
where rt.rn <= 10
group by
    rt.TagName,
    ua.GoldBadges,
    ua.SilverBadges,
    ua.BronzeBadges,
    CloseStatus,
    ua.CommentCount,
    ua.MaxPostScore,
    ua.FirstPostDate,
    ua.LastPostActivity,
    ua.Reputation,
    ua.DisplayName,
    ur.CreationYear,
    ur.CreationMonth,
    ur.QuestionsCount,
    ur.AnswersCount,
    ur.TotalPostScore,
    ur.MaxPostScore
having avg(rt.Score) > 5
order by AvgQuestionScore desc, AvgQuestionViews desc
limit 100;