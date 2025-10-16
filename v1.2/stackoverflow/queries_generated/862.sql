-- {"query": "862.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.8, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1574} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        0 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        c.Id,
        c.TagName,
        c.Count,
        r.Level + 1,
        r.Path || c.Id
    from Tags c
    join RecursiveTagHierarchy r on c.Id <> all(r.Path)
    where c.IsModeratorOnly = 0 and c.IsRequired = 0 and c.Count > 10
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        coalesce(u.Location, 'Unknown') as Location,
        row_number() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as loc_rank
    from Users u
    where u.Reputation > 1000 and u.LastAccessDate > current_date - interval '1 year'
),
UserBadgeCounts as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PopularQuestions as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        p.AcceptedAnswerId,
        row_number() over (order by p.Score desc, p.ViewCount desc) as Rank
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate > current_date - interval '2 years'
      and p.Score > 5
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.OwnerUserId is not null then 1 else 0 end) as AnsweredByRegisteredUsers
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
CloseReasonsSummary as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseVotesCount
    from PostHistory ph
    join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
UserRecentActivity as (
    select
        u.Id as UserId,
        max(p.CreationDate) as LastPostDate,
        max(c.CreationDate) as LastCommentDate,
        max(v.CreationDate) filter (where v.VoteTypeId = 2) as LastUpvoteDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
)
select
    pq.Id as QuestionId,
    pq.Title,
    pq.Score,
    pq.ViewCount,
    pq.Tags,
    pq.CreationDate,
    coalesce(ans.AnswerCount, 0) as AnswerCount,
    coalesce(ans.AvgAnswerScore, 0)::numeric(10,2) as AvgAnswerScore,
    coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(ans.AnsweredByRegisteredUsers, 0) as RegisteredUsersAnswerCount,
    coalesce(crs.CloseReason, 'Open') as CloseReason,
    coalesce(crs.CloseVotesCount, 0) as CloseVotesCount,
    u.DisplayName as OwnerDisplayName,
    u.Reputation as OwnerReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ur.LastPostDate,
    ur.LastCommentDate,
    ur.LastUpvoteDate,
    -- Complex string manipulation: count of tags and concatenated tag lengths
    array_length(string_to_array(trim(both '<>' from pq.Tags), '><'), 1) as TagCount,
    length(replace(coalesce(pq.Tags, ''), '><', ',')) as TagsLength,
    -- Window function example: rank of question score within its owner's questions
    rank() over (partition by pq.OwnerUserId order by pq.Score desc) as OwnerScoreRank,
    -- Correlated subquery with NULL logic
    (select count(*) from Comments c2 where c2.PostId = pq.Id and (c2.Text like '%error%' or c2.Text like '%fail%' or c2.Text like '%exception%')) as ErrorCommentsCount,
    -- Conditional expression with NULL handling
    case
        when pq.AcceptedAnswerId is not null then 1
        else 0
    end as HasAcceptedAnswer,
    -- Coalesce with nested NULL handling
    coalesce((select max(p2.Score) from Posts p2 where p2.ParentId = pq.Id and p2.Score is not null), 0) as MaxAnswerScoreFromSubquery
from PopularQuestions pq
left join AnswerStats ans on ans.QuestionId = pq.Id
left join CloseReasonsSummary crs on crs.PostId = pq.Id
left join Users u on u.Id = pq.OwnerUserId
left join UserBadgeCounts ub on ub.UserId = pq.OwnerUserId
left join UserRecentActivity ur on ur.UserId = pq.OwnerUserId
where pq.Rank <= 100
  and (ub.GoldBadges > 0 or ub.SilverBadges > 3 or ub.BronzeBadges > 5)
union
select
    null as QuestionId,
    'Summary' as Title,
    avg(p.Score) as Score,
    avg(p.ViewCount) as ViewCount,
    null as Tags,
    null as CreationDate,
    avg(ans.AnswerCount) as AnswerCount,
    avg(ans.AvgAnswerScore) as AvgAnswerScore,
    max(ans.MaxAnswerScore) as MaxAnswerScore,
    sum(ans.AnsweredByRegisteredUsers) as RegisteredUsersAnswerCount,
    'N/A' as CloseReason,
    0 as CloseVotesCount,
    null as OwnerDisplayName,
    null as OwnerReputation,
    sum(ub.GoldBadges) as GoldBadges,
    sum(ub.SilverBadges) as SilverBadges,
    sum(ub.BronzeBadges) as BronzeBadges,
    null as LastPostDate,
    null as LastCommentDate,
    null as LastUpvoteDate,
    null as TagCount,
    null as TagsLength,
    null as OwnerScoreRank,
    null as ErrorCommentsCount,
    null as HasAcceptedAnswer,
    null as MaxAnswerScoreFromSubquery
from PopularQuestions p
left join AnswerStats ans on ans.QuestionId = p.Id
left join Users u on u.Id = p.OwnerUserId
left join UserBadgeCounts ub on ub.UserId = p.OwnerUserId
where p.Rank <= 100
order by QuestionId nulls last, Score desc;