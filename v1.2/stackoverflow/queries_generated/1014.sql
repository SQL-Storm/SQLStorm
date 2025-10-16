-- {"query": "1014.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1131} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Date >= current_date - interval '1 year'
),
LatestUserActivity as (
    select 
        u.Id UserId,
        max(coalesce(p.LastActivityDate, c.CreationDate)) as LastActivity
    from Users u
    left join Posts p on u.Id = p.OwnerUserId
    left join Comments c on u.Id = c.UserId
    group by u.Id
),
TopAnswerers as (
    select 
        p.OwnerUserId as UserId,
        count(*) as AnswerCount,
        sum(p.Score) as TotalAnswerScore,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.OwnerUserId
    having count(*) > 10
),
QuestionStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.ViewCount,
        q.Score,
        q.AnswerCount,
        q.Tags,
        (select count(*) from Comments c where c.PostId = q.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = q.Id and v.VoteTypeId = 3) as DownVotes,
        case when q.ClosedDate is not null then 'Closed' else 'Open' end as Status,
        row_number() over (partition by q.ViewCount / nullif(nullif(q.Score,0),0)::float desc order by q.CreationDate desc) as PopularityRank
    from Posts q
    where q.PostTypeId = 1 and q.CreationDate > current_date - interval '2 years'
),
TagAggregates as (
    select 
        unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><')) as TagName,
        count(*) as TagQuestionCount,
        avg(q.Score) as AvgTagScore,
        sum(q.ViewCount) as TotalTagViews
    from Posts q
    where q.PostTypeId = 1
    group by TagName
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        count(*) over (partition by pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
)
select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    lub.BadgeName,
    lub.BadgeClass,
    lub.BadgeRank,
    t.AnswerCount,
    t.TotalAnswerScore,
    t.AvgAnswerScore,
    t.MaxAnswerScore,
    q.QuestionId,
    q.Title,
    q.CreationDate as QuestionCreated,
    q.ViewCount,
    q.Score as QuestionScore,
    q.AnswerCount as QuestionAnswerCount,
    q.CommentCount as QuestionCommentCount,
    q.UpVotes,
    q.DownVotes,
    q.Status as QuestionStatus,
    ta.TagName,
    ta.TagQuestionCount,
    ta.AvgTagScore,
    ta.TotalTagViews,
    dl.DuplicateCount,
    lua.LastActivity,
    case 
        when u.WebsiteUrl is not null and length(u.WebsiteUrl) > 0 then 
             lower(substring(u.WebsiteUrl from 'https?://([^/]+)'))
        else 'N/A'
    end as Domain,
    case 
        when u.Location is NULL then 'Unknown'
        when position(',' in u.Location) > 0 then substring(u.Location from 1 for position(',' in u.Location)-1)
        else u.Location
    end as LocationNormalized,
    length(coalesce(u.AboutMe, '')) as AboutMeLength,
    coalesce(lua.LastActivity < current_date - interval '30 days', false) as Inactive30Days,
    rank() over (partition by t.AnswerCount > 50 order by t.TotalAnswerScore desc nulls last) as TopAnswererRankAmongActive
from Users u
left join RecursiveUserBadges lub on u.Id = lub.UserId and lub.BadgeRank = 1
left join TopAnswerers t on u.Id = t.UserId
left join QuestionStats q on q.QuestionId = (
    select p.Id from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 order by p.ViewCount desc limit 1
)
left join TagAggregates ta on q.Tags like '%' || ta.TagName || '%'
left join DuplicateLinks dl on dl.PostId = q.QuestionId
left join LatestUserActivity lua on u.Id = lua.UserId
where u.Reputation > 1000
and (lub.BadgeName is not null or t.AnswerCount is not null)
order by t.TotalAnswerScore desc nulls last, q.ViewCount desc nulls last
limit 100;