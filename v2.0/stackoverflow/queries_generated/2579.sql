-- {"query": "2579.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1286} 
with RecursiveTagCounts as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        u.Id as OwnerUserId,
        u.DisplayName,
        array_length(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'), 1) as TagCount,
        row_number() over (partition by t.Id order by p.Score desc nulls last) as rn
    from 
        Tags t
        left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
        left join Users u on p.OwnerUserId = u.Id
    where 
        t.IsModeratorOnly = 0
),
TopPostsPerTag as (
    select * from RecursiveTagCounts where rn <= 3
),
UserBadgeRanks as (
    select 
        b.UserId,
        b.Name,
        b.Class,
        count(*) over (partition by b.UserId, b.Class) as BadgeCount,
        rank() over (partition by b.UserId order by b.Class) as BadgeRank
    from Badges b
),
UserReputationBands as (
    select 
        u.Id,
        u.DisplayName,
        u.Reputation,
        case 
            when u.Reputation < 100 then 'Novice'
            when u.Reputation between 100 and 999 then 'Intermediate'
            when u.Reputation >= 1000 then 'Expert'
            else 'Unknown'
        end as ReputationBand,
        coalesce((select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1), 0) as QuestionCount,
        coalesce((select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2), 0) as AnswerCount,
        coalesce((select count(*) from Comments c where c.UserId = u.Id), 0) as CommentCount
    from Users u
),
RecentPostActivity as (
    select 
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        ph.PostHistoryTypeId,
        ph.CreationDate as HistoryDate,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as rn
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id::int = ph.Comment::int
),
FilteredPostActivity as (
    select * from RecentPostActivity where rn = 1
),
UserVoteSummary as (
    select 
        v.UserId,
        vt.Name as VoteType,
        count(*) as VoteCount,
        sum(case when v.BountyAmount is not null then v.BountyAmount else 0 end) as TotalBounty
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId is not null
    group by v.UserId, vt.Name
),
AcceptedAnswerRates as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(a.Id) filter (where q.AcceptedAnswerId = a.Id) as AcceptedAnswers,
        count(a.Id) as TotalAnswers,
        case when count(a.Id) = 0 then 0 else round(100.0 * count(q.AcceptedAnswerId) filter (where q.AcceptedAnswerId = a.Id)/count(a.Id),2) end as AcceptanceRate
    from Users u
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join Posts q on q.AcceptedAnswerId = a.Id
    group by u.Id, u.DisplayName
)
select 
    t.TagName,
    t.Count as TotalTagCount,
    array_agg(distinct concat(p.Title, ' (Score: ', coalesce(p.Score,0), ')') order by p.Score desc nulls last) as TopQuestions,
    u.DisplayName as TopUserForTag,
    ub.Class as BadgeClass,
    ub.BadgeCount,
    ur.ReputationBand,
    ur.QuestionCount,
    ur.AnswerCount,
    ur.CommentCount,
    uv.VoteType,
    uv.VoteCount,
    uv.TotalBounty,
    a.AcceptanceRate,
    fpa.CloseReasonName,
    length(coalesce(t.TagName, '')) as TagNameLength,
    case when t.IsModeratorOnly = 1 then 'Moderator Only' else 'Public' end as TagVisibility
from Tags t
left join TopPostsPerTag p on p.TagName = t.TagName
left join Users u on u.Id = p.OwnerUserId
left join UserBadgeRanks ub on ub.UserId = u.Id and ub.BadgeRank = 1
left join UserReputationBands ur on ur.Id = u.Id
left join UserVoteSummary uv on uv.UserId = u.Id
left join AcceptedAnswerRates a on a.UserId = u.Id
left join FilteredPostActivity fpa on fpa.PostId = p.PostId
where t.Count > (select avg(Count) from Tags)
group by 
    t.TagName, t.Count, u.DisplayName, ub.Class, ub.BadgeCount, ur.ReputationBand, ur.QuestionCount, ur.AnswerCount, ur.CommentCount,
    uv.VoteType, uv.VoteCount, uv.TotalBounty, a.AcceptanceRate, fpa.CloseReasonName, t.IsModeratorOnly
having bool_or(p.Score > 5) or bool_or(p.Score is null)
union
select 
    'Summary' as TagName,
    count(*) as TotalTagCount,
    null::text[],
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null
from Tags
order by TagName nulls last, TotalTagCount desc;