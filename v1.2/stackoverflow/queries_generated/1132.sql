-- {"query": "1132.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.1, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1226} 
with RecursiveRecentPosts as (
    select 
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.OwnerUserId, p.Title,
        p.AcceptedAnswerId, p.ParentId,
        cast(p.Title as varchar(500)) as ComputedTitle,
        1 as Level
    from Posts p
    where p.CreationDate > current_date - interval '90 days'
    union all
    select 
        c.Id, c.PostTypeId, c.CreationDate, c.Score, c.ViewCount, c.OwnerUserId, c.Title,
        c.AcceptedAnswerId, c.ParentId,
        concat(r.ComputedTitle, ' -> ', coalesce(c.Title, '(no title)')) as ComputedTitle,
        r.Level + 1
    from Posts c
    join RecursiveRecentPosts r on c.ParentId = r.Id
    where r.Level < 3
), TopUsersCTE as (
    select 
        u.Id, u.DisplayName, u.Reputation, u.CreationDate,
        row_number() over (order by u.Reputation desc nulls last, u.Id) as RankByReputation,
        count(distinct b.Id) as BadgeCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesGiven,
        max(b.Date) as LastBadgeAwardedDate
    from Users u
    left join Badges b on b.UserId = u.Id and b.Class = 1
    left join (
        select UserId, count(*) as VoteCount
        from Votes 
        where UserId is not null and CreationDate > current_date - interval '365 days'
        group by UserId
    ) v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
    having count(distinct b.Id) >= 3
), PostAggregates as (
    select 
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionCount,
        count(*) filter (where p.PostTypeId = 2) as AnswerCount,
        avg(coalesce(p.Score,0)) as AverageScore,
        max(p.ViewCount) as MaxViewCount,
        bool_or(p.ClosedDate is not null) as HasClosedPosts
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
), ComplexFilter as (
    select 
        rp.Id,
        rp.PostTypeId,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        rp.OwnerUserId,
        rp.Title,
        rp.ComputedTitle,
        rp.Level
    from RecursiveRecentPosts rp
    where length(coalesce(rp.Title, '')) > 10 
      and rp.Score > (select avg(score) from Posts where PostTypeId = rp.PostTypeId and CreationDate > current_date - interval '1 year')
      and (rp.ViewCount > 100 or rp.Level > 1)
), FinalUserPostSet as (
    select 
        t.Id as UserId,
        t.DisplayName,
        t.Reputation,
        t.RankByReputation,
        t.BadgeCount,
        t.TotalVotesGiven,
        t.LastBadgeAwardedDate,
        pa.QuestionCount,
        pa.AnswerCount,
        pa.AverageScore,
        pa.MaxViewCount,
        pa.HasClosedPosts,
        cf.Id as RecentPostId,
        cf.PostTypeId as RecentPostTypeId,
        cf.CreationDate as RecentPostCreationDate,
        cf.Score as RecentPostScore,
        cf.ViewCount as RecentPostViewCount,
        cf.ComputedTitle as RecentPostComputedTitle,
        cf.Level as RecentPostRecursionLevel
    from TopUsersCTE t
    left join PostAggregates pa on pa.OwnerUserId = t.Id
    left join ComplexFilter cf on cf.OwnerUserId = t.Id
    where t.TotalVotesGiven > 50 or t.BadgeCount >= 5
)
select distinct 
    Fus.UserId,
    Fus.DisplayName,
    Fus.Reputation,
    Fus.RankByReputation,
    Fus.BadgeCount,
    Fus.TotalVotesGiven,
    to_char(Fus.LastBadgeAwardedDate, 'YYYY-MM-DD') as LastBadgeAwardedDate,
    Fus.QuestionCount,
    Fus.AnswerCount,
    round(Fus.AverageScore,2) as AverageScore,
    Fus.MaxViewCount,
    Fus.HasClosedPosts,
    Fus.RecentPostId,
    case Fus.RecentPostTypeId
        when 1 then 'Question'
        when 2 then 'Answer'
        when 3 then 'Wiki'
        else 'Other' 
    end as RecentPostType,
    to_char(Fus.RecentPostCreationDate, 'YYYY-MM-DD HH24:MI') as RecentPostCreated,
    Fus.RecentPostScore,
    Fus.RecentPostViewCount,
    Fus.RecentPostComputedTitle,
    Fus.RecentPostRecursionLevel,
    (select count(*) from Comments c where c.UserId = Fus.UserId and c.CreationDate > current_date - interval '180 days') as RecentCommentCount,
    (select count(*) from Votes v where v.UserId = Fus.UserId and v.VoteTypeId = 2 and v.CreationDate > current_date - interval '180 days') as RecentUpvotes,
    (select string_agg(distinct lt.Name, '; ') from PostLinks pl inner join LinkTypes lt on pl.LinkTypeId = lt.Id where pl.PostId in (select RecentPostId) and lt.Id in (1,3)) as RecentPostLinkTypes  
from FinalUserPostSet Fus
order by Reputation desc nulls last, BadgeCount desc, TotalVotesGiven desc
limit 100;