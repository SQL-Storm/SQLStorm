-- {"query": "1299.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1939} 
with RecursiveUserAccess as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        row_number() over (order by u.Reputation desc nulls last, u.Id) as RankByReputation
    from Users u
    where u.Reputation > 1000
), 
UserBadgeSummary as (
    select
        b.UserId,
        count(*) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        string_agg(distinct b.Name, ', ' order by b.Name) as DistinctBadgeNames
    from Badges b
    where b.UserId in (select UserId from RecursiveUserAccess)
    group by b.UserId
), 
QuestionAnswerStats as (
    select
        p.Id as PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        coalesce(p.AnswerCount,0) as AnswerCount,
        p.CreationDate as PostCreationDate,
        -- rank posts by score within each user and post type:
        row_number() over (partition by p.OwnerUserId, p.PostTypeId order by p.Score desc nulls last) as RankPostScore,
        -- extract first tag from Tags array or assign 'NoTag'
        case
          when p.Tags is null then 'NoTag'
          else (regexp_split_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'))[1]
        end as FirstTag
    from Posts p
    where p.OwnerUserId in (select UserId from RecursiveUserAccess)
      and p.PostTypeId in (1,2)
),
UserTopPosts as (
    select
        q.PostId as QuestionId,
        a.PostId as AnswerId,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        q.AnswerCount,
        q.PostCreationDate as QuestionCreationDate,
        a.Score as AnswerScore,
        a.PostCreationDate as AnswerCreationDate,
        q.FirstTag,
        coalesce((select ph.CreationDate 
                  from PostHistory ph 
                  where ph.PostId = q.PostId and ph.PostHistoryTypeId = 10
                  order by ph.CreationDate desc limit 1), null) as LastCloseDate,
        ab.TotalBadges,
        ab.GoldBadges,
        ab.SilverBadges,
        ab.BronzeBadges,
        ab.DistinctBadgeNames
    from QuestionAnswerStats q
    left join QuestionAnswerStats a on a.ParentId = q.PostId and a.RankPostScore = 1 and a.PostTypeId = 2
    join UserBadgeSummary ab on ab.UserId = q.OwnerUserId
    where q.PostTypeId = 1
      and q.RankPostScore <= 5
),
AnswerAverageScores as (
    select
        a.ParentId,
        avg(a.Score) as AvgAnswerScore
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
FilteredPostLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        lt.Name as LinkTypeName,
        pl.CreationDate
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    where lt.Name in ('Linked', 'Duplicate')
),
TaggedPosts as (
    select
        p.Id,
        p.Title,
        trim(tg.tag) as TagName
    from Posts p
    cross join lateral unnest(regexp_split_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as tg(tag)
    where p.PostTypeId = 1
),
ClosingReasonSummary as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on ph.Comment::int = crt.Id
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
AggregateUserActivities as (
    select
        u.Id as UserId,
        coalesce(u.Views,0) as Views,
        coalesce(u.UpVotes,0) as UpVotes,
        coalesce(u.DownVotes,0) as DownVotes,
        coalesce(votes_counts.UpVoteCount,0) as VoteReceives,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (2,5)) as EditCount,
        max(ph.CreationDate) filter (where ph.UserId = u.Id) as LastEditDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join (
        select p.OwnerUserId, count(v.Id) as UpVoteCount
        from Votes v 
        join Posts p on v.PostId = p.Id
        where v.VoteTypeId = 2
        group by p.OwnerUserId
    ) votes_counts on votes_counts.OwnerUserId = u.Id
    group by u.Id, u.Views, u.UpVotes, u.DownVotes, votes_counts.UpVoteCount
)
select distinct
    rsa.UserId,
    rsa.DisplayName,
    rsa.Reputation,
    iby.TotalBadges,
    iby.GoldBadges,
    iby.SilverBadges,
    iby.BronzeBadges,
    ipq.QuestionId,
    ipq.QuestionScore,
    ipq.QuestionViews,
    ipq.AnswerCount,
    ipq.AnswerId,
    ipq.AnswerScore,
    ipq.FirstTag,
    ipq.LastCloseDate,
    ca.CloseReasonName,
    ca.CloseCount,
    coalesce(aus.Views,0) as UserViews,
    aus.UpVotes as UserUpVotesGiven,
    aus.DownVotes as UserDownVotesGiven,
    aus.VoteReceives as UserUpVotesReceived,
    aus.EditCount as UserEditActions,
    aus.LastEditDate,
    -- Using Window function for calculating user's average question score
    avg(ipq.QuestionScore) over (partition by rsa.UserId) as AvgUserQuestionScore,
    avg(ipq.AnswerScore) over (partition by rsa.UserId) as AvgUserAnswerScore,
    -- Computing length of user’s display name concatenated with first badge
    length(rsa.DisplayName || coalesce(split_part(iby.DistinctBadgeNames, ',', 1), '')) as DisplayNameBadgeLen,
    -- String reversed first tag name or 'None'
    reverse(coalesce(ipq.FirstTag, 'None')) as ReversedFirstTag,
    -- Demonstration of complex CASE/NULL logic
    case 
        when ipq.LastCloseDate is not null and ipq.LastCloseDate > current_date - interval '1 year' then true
        else false
    end as RecentlyClosed,
    -- Correlated subquery to get count of comments user has made on questions
    (
        select count(*)
        from Comments c
        join Posts p2 on c.PostId = p2.Id and p2.PostTypeId = 1
        where c.UserId = rsa.UserId
    ) as QuestionCommentsCount
from RecursiveUserAccess rsa
join UserBadgeSummary iby on rsa.UserId = iby.UserId
left join UserTopPosts ipq on ipq.OwnerUserId = rsa.UserId
left join ClosingReasonSummary ca on ca.PostId = ipq.QuestionId
left join AggregateUserActivities aus on aus.UserId = rsa.UserId
where (ipq.AnswerScore is null or ipq.AnswerScore >= 0)
union
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    0 as TotalBadges,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    null as QuestionId,
    null as QuestionScore,
    null as QuestionViews,
    0 as AnswerCount,
    null as AnswerId,
    null as AnswerScore,
    'NoTag' as FirstTag,
    null as LastCloseDate,
    null as CloseReasonName,
    0 CloseCount,
    coalesce(u.Views,0) as UserViews,
    coalesce(u.UpVotes,0) as UserUpVotesGiven,
    coalesce(u.DownVotes,0) as UserDownVotesGiven,
    0 as UserUpVotesReceived,
    0 as UserEditActions,
    null as LastEditDate,
    null as AvgUserQuestionScore,
    null as AvgUserAnswerScore,
    length(u.DisplayName) as DisplayNameBadgeLen,
    'NoTag' as ReversedFirstTag,
    false as RecentlyClosed,
    0 as QuestionCommentsCount
from Users u
where u.Id not in (select UserId from RecursiveUserAccess)
order by Reputation desc nulls last, UserId
limit 50;