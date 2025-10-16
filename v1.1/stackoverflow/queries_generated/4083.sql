-- {"query": "4083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1764} 
with RecursiveTagUsage as (
    select
        t.Id as TagId,
        t.TagName,
        count(p.Id) as QuestionCount,
        avg(p.Score) as AvgScore,
        max(p.ViewCount) as MaxViews,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedCount
    from Tags t
    left join Posts p on p.PostTypeId = 1 and p.Tags like concat('%<', t.TagName, '>%')
    group by t.Id, t.TagName
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as Questions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as Answers,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgScore,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxScore,
        bool_or(p.AcceptedAnswerId is not null and p.OwnerUserId = u.Id) as HasAcceptedAnswer,
        row_number() over (partition by u.Id order by max(p.LastActivityDate) desc) as LastActiveRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
LatestPostComments as (
    select
        c.PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
AnswerWithVotes as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.Score as AnswerScore,
        v.VoteTypeId,
        count(v.Id) as VoteCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Posts a
    left join Votes v on v.PostId = a.Id
    where a.PostTypeId = 2
    group by a.Id, a.ParentId, a.Score, v.VoteTypeId
),
QuestionsDetails as (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score as QuestionScore,
        q.ViewCount,
        q.AcceptedAnswerId,
        coalesce(lpc.CommentCount,0) as QuestionCommentCount,
        coalesce(u.DisplayName, 'Unknown') as OwnerName,
        coalesce(u.Reputation, 0) as OwnerReputation,
        least(1000, q.ViewCount) * q.Score::numeric / nullif(greatest(1, date_part('day', now() - q.CreationDate)),1) as HotnessScore,
        array(
            select distinct unnest(string_to_array(substring(q.Tags from 2 for char_length(q.Tags) - 2), '><'))
        ) as TagArray
    from Posts q
    left join LatestPostComments lpc on lpc.PostId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    where q.PostTypeId = 1
),
AcceptedAnswerStats as (
    select
        q.QuestionId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        (select count(*) from Votes v2 where v2.PostId = a.Id and v2.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v3 where v3.PostId = a.Id and v3.VoteTypeId = 3) as DownVotes,
        case when a.CreationDate <= q.CreationDate + interval '1 day' then true else false end as AcceptedEarly
    from QuestionsDetails q
    left join Posts a on a.Id = q.AcceptedAnswerId
),
UsersWithGoldBadges as (
    select
        b.UserId,
        count(*) as GoldBadgeCount
    from Badges b
    where b.Class = 1
    group by b.UserId
)
select distinct
    q.QuestionId,
    q.Title,
    q.CreationDate,
    q.QuestionScore,
    q.ViewCount,
    q.HotnessScore,
    q.OwnerName,
    q.OwnerReputation,
    q.QuestionCommentCount,
    array_to_string(q.TagArray, ', ') as Tags,
    a.AnswerId,
    a.AnswerScore,
    a.UpVotes,
    a.DownVotes,
    a.AcceptedEarly,
    coalesce(uwg.GoldBadgeCount,0) as OwnerGoldBadges,
    ups.TotalPosts,
    ups.Questions,
    ups.Answers,
    ups.AvgScore,
    ups.MaxScore,
    ups.HasAcceptedAnswer,
    ups.LastActiveRank,
    pht.Name as LastPostHistoryType,
    case when ph.PostHistoryTypeId in (10, 12, 52) then true else false end as PostStatusFlag
from QuestionsDetails q
left join AcceptedAnswerStats a on a.QuestionId = q.QuestionId
left join UsersWithGoldBadges uwg on uwg.UserId = (select OwnerUserId from Posts where Id = q.QuestionId)
left join UserPostStats ups on ups.UserId = (select OwnerUserId from Posts where Id = q.QuestionId)
left join LATERAL (
    select ph2.PostHistoryTypeId, pht2.Name, ph2.CreationDate
    from PostHistory ph2
    inner join PostHistoryTypes pht2 on pht2.Id = ph2.PostHistoryTypeId
    where ph2.PostId = q.QuestionId
    order by ph2.CreationDate desc nulls last
    limit 1
) ph on true
left join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
where q.HotnessScore > (
    select percentile_cont(0.75) within group (order by HotnessScore) from QuestionsDetails
)
and (a.AnswerScore is null or a.AnswerScore < q.QuestionScore * 0.5 or a.AcceptedEarly = false)
union
select
    q2.QuestionId,
    q2.Title,
    q2.CreationDate,
    q2.QuestionScore,
    q2.ViewCount,
    q2.HotnessScore,
    q2.OwnerName,
    q2.OwnerReputation,
    q2.QuestionCommentCount,
    array_to_string(q2.TagArray, ', ') as Tags,
    null as AnswerId,
    null as AnswerScore,
    null as UpVotes,
    null as DownVotes,
    null as AcceptedEarly,
    coalesce(uwg2.GoldBadgeCount,0) as OwnerGoldBadges,
    ups2.TotalPosts,
    ups2.Questions,
    ups2.Answers,
    ups2.AvgScore,
    ups2.MaxScore,
    ups2.HasAcceptedAnswer,
    ups2.LastActiveRank,
    pht2.Name as LastPostHistoryType,
    case when ph2.PostHistoryTypeId in (10, 12, 52) then true else false end as PostStatusFlag
from QuestionsDetails q2
left join UsersWithGoldBadges uwg2 on uwg2.UserId = (select OwnerUserId from Posts where Id = q2.QuestionId)
left join UserPostStats ups2 on ups2.UserId = (select OwnerUserId from Posts where Id = q2.QuestionId)
left join LATERAL (
    select ph3.PostHistoryTypeId, pht3.Name, ph3.CreationDate
    from PostHistory ph3
    inner join PostHistoryTypes pht3 on pht3.Id = ph3.PostHistoryTypeId
    where ph3.PostId = q2.QuestionId
    order by ph3.CreationDate desc nulls last
    limit 1
) ph2 on true
left join PostHistoryTypes pht2 on pht2.Id = ph2.PostHistoryTypeId
where q2.AcceptedAnswerId is null
order by HotnessScore desc, OwnerGoldBadges desc, QuestionScore desc
limit 100;