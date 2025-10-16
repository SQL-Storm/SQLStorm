-- {"query": "1233.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1547} 
with RecursiveTagDescendants as (
    select t.Id, t.TagName, t.WikiPostId, t.ExcerptPostId, 0 as Level
    from Tags t
    where t.Id in (
        select Id from Tags where TagName ilike 'sql%'
    )
    union all
    select child.Id, child.TagName, child.WikiPostId, child.ExcerptPostId, r.Level + 1
    from Tags child
    join RecursiveTagDescendants r on child.Id = r.Id + 1
    where r.Level < 3
),
UsersRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1 and p.CreationDate > current_date - interval '90 days') as RecentQuestions,
        count(distinct p.Id) filter (where p.PostTypeId = 2 and p.CreationDate > current_date - interval '90 days') as RecentAnswers,
        count(distinct v.Id) filter (where v.CreationDate > current_date - interval '90 days') as RecentVotes,
        count(distinct b.Id) filter (where b.Date > current_date - interval '90 days') as RecentBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location
),
PostScoreMovingAvg as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        avg(p.Score) over (
            partition by p.PostTypeId 
            order by p.CreationDate rows between 2 preceding and current row
        ) as ScoreMovingAvg,
        lag(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.CreationDate) as NextScore
    from Posts p
    where p.CreationDate > current_date - interval '1 year'
),
PostLinksWithTypes as (
    select 
        pl.Id,
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where pl.CreationDate > current_date - interval '180 days'
),
QuestionsWithAcceptedAnswerBadges as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.AnswerCount,
        aa.Id as AcceptedAnswerId,
        aa.Score as AcceptedAnswerScore,
        aa.CreationDate as AcceptedAnswerCreation,
        u.DisplayName as QuestionOwner,
        
        -- Correlated subquery to count badges of answer owner if exists
        (select count(b.Id) from Badges b where b.UserId = aa.OwnerUserId) as AcceptedAnswerOwnerBadgeCount
        
    from Posts q
    left join Posts aa on aa.Id = q.AcceptedAnswerId and aa.PostTypeId = 2
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1 and q.AnswerCount > 0
        and q.CreationDate > current_date - interval '1 year'
),
EditsAndClosuresLastMonth as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastEditDate,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotes,
        sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenVotes
    from PostHistory ph
    where ph.CreationDate > current_date - interval '30 days'
    group by ph.PostId
),
CombinedActivity as (
    select 
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.RecentQuestions,
        u.RecentAnswers,
        u.RecentVotes,
        u.RecentBadges,
        coalesce(e.CloseVotes,0) as RecentCloseVotes,
        coalesce(e.ReopenVotes,0) as RecentReopenVotes,
        pvl.LinkCount,
        row_number() over (partition by u.Location order by u.Reputation desc) as UserRankInLocation,
        count(distinct pl.PostId) over (partition by u.UserId) as PostsWithLinksCreated
    from UsersRecentActivity u
    left join (
        select OwnerUserId, count(*) as LinkCount
        from Posts p
        join PostLinks pl on pl.PostId = p.Id
        group by OwnerUserId
    ) pvl on pvl.OwnerUserId = u.UserId
    left join EditsAndClosuresLastMonth e on e.PostId in (
        select p.Id from Posts p where p.OwnerUserId = u.UserId
    )
)
select
    c.UserId,
    c.DisplayName,
    c.Reputation,
    c.Location,
    
    c.RecentQuestions,
    c.RecentAnswers,
    c.RecentVotes,
    c.RecentBadges,
    c.RecentCloseVotes,
    c.RecentReopenVotes,
    c.LinkCount,
    c.UserRankInLocation,
    c.PostsWithLinksCreated,
    
    t.Level as TagDepth,
    t.TagName,
    
    qwa.QuestionId,
    qwa.Title,
    qwa.CreationDate as QuestionCreated,
    qwa.QuestionScore,
    qwa.AnswerCount,
    qwa.AcceptedAnswerId,
    qwa.AcceptedAnswerScore,
    qwa.AcceptedAnswerCreation,
    qwa.QuestionOwner,
    qwa.AcceptedAnswerOwnerBadgeCount,
    
    psm.Score,
    psm.ScoreMovingAvg,
    psm.PrevScore,
    psm.NextScore
    
from CombinedActivity c
left join RecursiveTagDescendants t on t.Id = (
    select min(TagId) from (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))::text as TagText,
            (select Id from Tags where TagName = unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))) as TagId
        from Posts p where p.OwnerUserId = c.UserId limit 1
    ) sub where TagId is not null
)
left join QuestionsWithAcceptedAnswerBadges qwa on qwa.QuestionId in (
    select p.Id from Posts p where p.OwnerUserId = c.UserId and p.PostTypeId = 1
)
left join PostScoreMovingAvg psm on psm.Id = qwa.AcceptedAnswerId
where c.Reputation > 1000
  and (c.RecentQuestions + c.RecentAnswers) > 5
order by c.Reputation desc NULLS LAST, c.DisplayName asc
limit 100;