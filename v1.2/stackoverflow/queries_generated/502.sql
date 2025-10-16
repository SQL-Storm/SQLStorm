-- {"query": "502.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1271} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        0 as Depth,
        array[u.Id] as VisitedUsers
    from Users u
    where u.Reputation > 1000
    union all
    select
        v.UserId,
        u2.DisplayName,
        u2.Reputation,
        u2.CreationDate,
        u2.LastAccessDate,
        r.Depth + 1,
        r.VisitedUsers || v.UserId
    from RecursiveUserActivity r
    join Votes v on v.UserId = r.UserId
    join Users u2 on u2.Id = v.UserId
    where r.Depth < 2 and not v.UserId = any(r.VisitedUsers)
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId = 1 and p.Score > 10 and p.ViewCount > 1000
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        a.Id as AcceptedAnswerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.Reputation as AnswererReputation,
        count(c.Id) as AnswerCommentsCount
    from Posts q
    left join Posts a on a.Id = q.AcceptedAnswerId
    left join Users u on u.Id = a.OwnerUserId
    left join Comments c on c.PostId = a.Id
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
    group by q.Id, q.OwnerUserId, a.Id, a.Score, a.CreationDate, u.Reputation
),
BadgeCounts as (
    select
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges
    group by UserId
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        coalesce(bc.GoldBadges, 0) as GoldBadges,
        coalesce(bc.SilverBadges, 0) as SilverBadges,
        coalesce(bc.BronzeBadges, 0) as BronzeBadges,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        max(p.LastActivityDate) as LastActivityDate
    from Users u
    left join Badges bc on bc.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
),
UserRecentComments as (
    select
        c.UserId,
        c.PostId,
        c.CreationDate,
        c.Text,
        row_number() over (partition by c.UserId order by c.CreationDate desc) as rn
    from Comments c
    where c.UserId is not null
),
UserTopComment as (
    select
        urc.UserId,
        urc.PostId,
        urc.CreationDate,
        urc.Text
    from UserRecentComments urc
    where urc.rn = 1
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.QuestionCount,
    u.AnswerCount,
    u.AvgPostScore,
    u.LastActivityDate,
    tq.Title as TopQuestionTitle,
    tq.Score as TopQuestionScore,
    tq.ViewCount as TopQuestionViews,
    a.AnswerScore,
    a.AnswererReputation,
    a.AnswerCommentsCount,
    dl.OriginalTitle as DuplicateOriginalTitle,
    dl.DuplicateTitle as DuplicatePostTitle,
    dl.CreationDate as DuplicateLinkDate,
    utc.Text as LatestCommentText,
    case
        when u.AvgPostScore > 50 then 'High Scorer'
        when u.AvgPostScore between 20 and 50 then 'Medium Scorer'
        else 'Low Scorer'
    end as ScorerCategory,
    dense_rank() over (order by u.Reputation desc) as ReputationRank
from UserPostStats u
left join TopQuestions tq on tq.OwnerUserId = u.UserId and tq.rn = 1
left join AcceptedAnswerStats a on a.OwnerUserId = u.UserId
left join DuplicateLinks dl on dl.PostId = tq.Id
left join UserTopComment utc on utc.UserId = u.UserId
where u.Reputation > 500
order by u.Reputation desc, u.GoldBadges desc, u.AvgPostScore desc
limit 100;