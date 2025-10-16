-- {"query": "876.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1319} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc, b.Class asc) as rn
    from Users u
    left join Badges b on u.Id = b.UserId
), 
TopBadgesPerUser as (
    select UserId, DisplayName, BadgeName, Class
    from RecursiveUserBadges
    where rn <= 3
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        coalesce(
            (select count(*) from Posts a where a.ParentId = p.Id and a.Score > 0),
            0
        ) as PositiveAnswerCount,
        coalesce(
            (select avg(a.Score) from Posts a where a.ParentId = p.Id and a.Score is not null),
            0
        ) as AvgAnswerScore,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate asc) as UserTopQuestionRank
    from Posts p
    where p.PostTypeId = 1
),
PostHistoryEdits as (
    select 
        ph.PostId,
        ph.UserId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        count(*) over (partition by ph.PostId) as TotalEdits,
        max(ph.CreationDate) over (partition by ph.PostId) as LastEditDate
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
UserPostScores as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as TotalQuestions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as TotalAnswers,
        sum(p.Score) as TotalPostScore,
        avg(p.Score) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    group by u.Id, u.DisplayName
),
DuplicateLinks as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
),
QuestionDuplicates as (
    select 
        q.Id as QuestionId,
        q.Title,
        count(distinct dl.RelatedPostId) as DuplicateCount,
        max(dl.CreationDate) as LastDuplicateLinked
    from Posts q
    left join DuplicateLinks dl on q.Id = dl.PostId
    where q.PostTypeId = 1
    group by q.Id, q.Title
),
UserQuestionSummary as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(q.Id) as QuestionCount,
        sum(q.Score) as TotalQuestionScore,
        avg(q.Score) as AvgQuestionScore,
        sum(q.AnswerCount) as TotalAnswersToQuestions,
        sum(q.PositiveAnswerCount) as PositiveAnswersCount,
        max(q.Score) as MaxQuestionScore
    from Users u
    left join QuestionStats q on u.Id = q.OwnerUserId
    group by u.Id, u.DisplayName
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    us.TotalPosts,
    us.TotalQuestions,
    us.TotalAnswers,
    us.TotalPostScore,
    us.AvgPostScore,
    us.MaxPostScore,
    us.HasClosedPosts,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(u.Location, 'Unknown') as UserLocation,
    coalesce(u.WebsiteUrl, 'N/A') as Website,
    string_agg(distinct tb.BadgeName || ' (' || case tb.Class when 1 then 'Gold' when 2 then 'Silver' when 3 then 'Bronze' else 'Other' end || ')', ', ') 
        filter (where tb.BadgeName is not null) over (partition by u.Id) as TopBadges,
    qs.QuestionCount,
    qs.TotalQuestionScore,
    qs.AvgQuestionScore,
    qs.TotalAnswersToQuestions,
    qs.PositiveAnswersCount,
    qs.MaxQuestionScore,
    qd.DuplicateCount,
    qd.LastDuplicateLinked,
    ph.TotalEdits,
    ph.LastEditDate,
    case 
        when us.HasClosedPosts then 'Yes'
        else 'No'
    end as HasClosedPostsText,
    case 
        when u.Reputation >= 10000 then 'Expert'
        when u.Reputation >= 5000 then 'Experienced'
        when u.Reputation >= 1000 then 'Intermediate'
        else 'Newbie'
    end as ReputationLevel
from Users u
left join UserPostScores us on u.Id = us.UserId
left join UserQuestionSummary qs on u.Id = qs.UserId
left join (
    select PostId, max(TotalEdits) as TotalEdits, max(LastEditDate) as LastEditDate
    from PostHistoryEdits
    group by PostId
) ph on ph.PostId = (
    select p.Id from Posts p 
    where p.OwnerUserId = u.Id and p.PostTypeId = 1 
    order by p.Score desc limit 1
)
left join QuestionDuplicates qd on qd.QuestionId = (
    select p.Id from Posts p 
    where p.OwnerUserId = u.Id and p.PostTypeId = 1 
    order by p.Score desc limit 1
)
left join TopBadgesPerUser tb on tb.UserId = u.Id
where u.Reputation > 100
order by us.TotalPostScore desc nulls last, u.Reputation desc
limit 100;