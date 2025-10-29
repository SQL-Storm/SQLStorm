-- {"query": "2518.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1567}
with recursive RecursiveTagHierarchy as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        cast(t.TagName as varchar(100)) as FullPath
    from Tags t
    where t.IsRequired = true and t.IsModeratorOnly = false
    union all
    select 
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        cast(r.FullPath || '>' || t2.TagName as varchar(100)) as FullPath
    from Tags t2
    inner join RecursiveTagHierarchy r on t2.Id = r.Id + 1
    where t2.IsRequired = false and t2.IsModeratorOnly = false
      and r.Level < 3
), 
UserActivityWindowed as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p2.Id) filter (where p2.PostTypeId = 2) as AnswerCount,
        row_number() over (partition by u.Location order by u.Reputation desc, u.Views desc) as LocationRank,
        dense_rank() over (order by u.Reputation desc) as GlobalReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Posts p2 on p2.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views
),
TopQuestionsWithAcceptedAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        aa.Id as AcceptedAnswerId,
        aa.Score as AcceptedAnswerScore,
        aa.OwnerUserId as AnswerOwnerId,
        u.DisplayName as QuestionOwner,
        aa.OwnerDisplayName as AcceptedAnswerOwner,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as QuestionUpVotes,
        (select count(*) from Votes v where v.PostId = aa.Id and v.VoteTypeId = 2) as AnswerUpVotes,
        (select string_agg(distinct ph.Name, ', ') from PostHistoryTypes ph where ph.Id in (
            select ph2.PostHistoryTypeId from PostHistory ph2 where ph2.PostId = q.Id and ph2.PostHistoryTypeId in (4,5,6)
        )) as HistoryTypes
    from Posts q
    left join Posts aa on aa.Id = q.AcceptedAnswerId
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1
      and q.CreationDate > (cast('2024-10-01' as date) - interval '1 year')
      and q.Score > 5
),
CombinedUserBadges as (
    select 
        b.UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        b.Date,
        case 
            when b.Class = 1 then 'Gold'
            when b.Class = 2 then 'Silver'
            else 'Bronze' 
        end as BadgeClassName,
        row_number() over (partition by b.UserId order by b.Date desc) as BadgeRank
    from Badges b
    inner join Users u on u.Id = b.UserId
    where b.Date > (cast('2024-10-01' as date) - interval '6 months')
),
FinalSelection as (
    select 
        t.QuestionId,
        t.Title,
        t.CreationDate,
        t.Score,
        t.ViewCount,
        t.Tags,
        t.AcceptedAnswerId,
        t.AcceptedAnswerScore,
        t.QuestionOwner,
        t.AcceptedAnswerOwner,
        t.QuestionUpVotes,
        t.AnswerUpVotes,
        ua.DisplayName,
        ua.Reputation,
        ua.Location,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.LocationRank,
        ua.GlobalReputationRank,
        cb.BadgeName,
        cb.BadgeClassName
    from TopQuestionsWithAcceptedAnswers t
    left join UserActivityWindowed ua on ua.UserId = cast(t.QuestionOwner as integer)
    left join CombinedUserBadges cb on cb.UserId = ua.UserId and cb.BadgeRank = 1
    where (t.Score * 2 + t.ViewCount / 100.0) > (
        select avg(q.Score)*2 + avg(q.ViewCount)/100.0 from Posts q where q.PostTypeId = 1 and q.CreationDate > (cast('2024-10-01' as date) - interval '1 year')
    )
    and ua.Location is not null
    order by t.ViewCount desc, t.Score desc
    limit 50
)
select 
    f.QuestionId,
    f.Title,
    substring(f.Tags from 1 for 100) as SampleTags,
    f.CreationDate,
    f.Score,
    f.ViewCount,
    f.AcceptedAnswerId,
    f.AcceptedAnswerScore,
    coalesce(f.BadgeName, 'No Badge') as RecentTopBadge,
    f.BadgeClassName,
    f.QuestionOwner,
    f.AcceptedAnswerOwner,
    f.QuestionUpVotes,
    f.AnswerUpVotes,
    f.DisplayName as OwnerDisplayName,
    f.Reputation,
    f.Location,
    f.QuestionCount,
    f.AnswerCount,
    f.LocationRank,
    f.GlobalReputationRank,
    case 
        when f.Score > 10 and f.ViewCount > 1000 then 'Hot Topic'
        when f.Score > 5 then 'Popular'
        else 'Normal'
    end as PopularityCategory
from FinalSelection f
where exists (
    select 1 from RecursiveTagHierarchy r where position(r.TagName in f.Tags) > 0
)
union
select 
    p.Id as QuestionId,
    p.Title,
    substring(p.Tags from 1 for 100) as SampleTags,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    null as AcceptedAnswerId,
    null as AcceptedAnswerScore,
    'No Badge' as RecentTopBadge,
    null as BadgeClassName,
    u.DisplayName as QuestionOwner,
    null as AcceptedAnswerOwner,
    (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as QuestionUpVotes,
    null as AnswerUpVotes,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    u.Location,
    null as QuestionCount,
    null as AnswerCount,
    null as LocationRank,
    null as GlobalReputationRank,
    'Unanswered' as PopularityCategory
from Posts p
left join Users u on u.Id = p.OwnerUserId
where p.PostTypeId = 1
  and p.AcceptedAnswerId is null
  and p.CreationDate > (cast('2024-10-01' as date) - interval '30 days')
  and not exists (
      select 1 from Votes v where v.PostId = p.Id and v.VoteTypeId = 2
  )
  and exists (
      select 1 from RecursiveTagHierarchy r where position(r.TagName in p.Tags) > 0
  )
order by Score desc, ViewCount desc
limit 25;