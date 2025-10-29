-- {"query": "2765.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1515} 

with RecursiveUserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        b.Name as BadgeName,
        b.Class,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    where b.Class is not null
),
TopUsersWithGoldBadges as (
    select distinct UserId, DisplayName
    from RecursiveUserBadges
    where Class = 1 -- Gold badges
),
PostScoreStats as (
    select 
        p.OwnerUserId,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(avg(p.Score),0) as AvgPostScore,
        max(p.Score) as MaxPostScore,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 10) as ClosedCount
    from Posts p
    left join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId = 10
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
UserPostLinkAgg as (
    select 
        u.Id as UserId,
        count(distinct pl.Id) filter (where pl.LinkTypeId = 1) as LinksMade,
        count(distinct pl.Id) filter (where pl.LinkTypeId = 3) as DuplicatesMarked
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostLinks pl on pl.PostId = p.Id
    group by u.Id
),
UserActivityWindow as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        count(c.Id) as CommentsCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        lag(u.LastAccessDate) over (order by u.CreationDate) as PreviousUserLastAccessDate,
        lead(u.LastAccessDate) over (order by u.CreationDate) as NextUserLastAccessDate
    from Users u
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.LastAccessDate
),
ComplexUserStats as (
    select
        u.UserId,
        u.DisplayName,
        coalesce(pss.QuestionCount,0) as QuestionCount,
        coalesce(pss.AnswerCount,0) as AnswerCount,
        coalesce(pss.AvgPostScore,0.0) as AvgPostScore,
        coalesce(pss.ClosedCount,0) as ClosedPostsCount,
        coalesce(upla.LinksMade,0) as LinksMade,
        coalesce(upla.DuplicatesMarked,0) as DuplicatesMarked,
        ua.CommentsCount,
        ua.UpVotesReceived,
        ua.DownVotesReceived,
        case 
            when ua.UpVotesReceived + ua.DownVotesReceived = 0 then null
            else (ua.UpVotesReceived::float) / (ua.UpVotesReceived + ua.DownVotesReceived)
        end as UpVoteRatio,
        ROW_NUMBER() OVER (ORDER BY coalesce(pss.AvgPostScore,0) DESC) AS RankByAvgPostScore
    from TopUsersWithGoldBadges u
    left join PostScoreStats pss on u.UserId = pss.OwnerUserId or u.UserId = pss.OwnerUserId
    left join UserPostLinkAgg upla on u.UserId = upla.UserId
    left join UserActivityWindow ua on u.UserId = ua.UserId
),
ClosedQuestionDetails as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        ph.CreationDate as CloseDateTime,
        crt.Name as CloseReasonName,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 6) as CloseVoteCount,
        (select count(*) from Comments c where c.PostId = p.Id and c.Text ilike '%close%') as CloseRelatedComments,
        array_to_string(array_agg(distinct t.TagName), ', ') as TagList,
        row_number() over (partition by p.OwnerUserId order by ph.CreationDate desc) as CloseRankPerUser
    from Posts p
    join PostHistory ph on p.Id = ph.PostId and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Tags t on t.Id in (
        select unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><'))::int 
        where p.Tags is not null
    )
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.Title, p.Tags, ph.CreationDate, crt.Name
)
select 
    c.UserId,
    c.DisplayName,
    c.QuestionCount,
    c.AnswerCount,
    c.AvgPostScore,
    c.ClosedPostsCount,
    c.LinksMade,
    c.DuplicatesMarked,
    c.CommentsCount,
    c.UpVotesReceived,
    c.DownVotesReceived,
    round(c.UpVoteRatio::numeric,3) as UpVoteRatio,
    c.RankByAvgPostScore,
    cq.QuestionId,
    cq.Title as ClosedQuestionTitle,
    cq.CloseDateTime,
    cq.CloseReasonName,
    cq.CloseVoteCount,
    cq.CloseRelatedComments,
    cq.TagList
from ComplexUserStats c
left join ClosedQuestionDetails cq on cq.OwnerUserId = c.UserId and cq.CloseRankPerUser = 1
where c.AvgPostScore > 1.5
order by c.RankByAvgPostScore
limit 50
union
select 
    u.Id as UserId,
    u.DisplayName,
    0 as QuestionCount,
    0 as AnswerCount,
    0.0 as AvgPostScore,
    0 as ClosedPostsCount,
    0 as LinksMade,
    0 as DuplicatesMarked,
    0 as CommentsCount,
    0 as UpVotesReceived,
    0 as DownVotesReceived,
    null as UpVoteRatio,
    null as RankByAvgPostScore,
    null as QuestionId,
    null as ClosedQuestionTitle,
    null as CloseDateTime,
    null as CloseReasonName,
    null as CloseVoteCount,
    null as CloseRelatedComments,
    null as TagList
from Users u
where u.Reputation > 50000 and u.Id not in (
    select UserId from ComplexUserStats
)
order by u.Reputation desc
limit 10;
