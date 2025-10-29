-- {"query": "2570.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1450} 
with RecursiveUserReputationGrowth as (
    select
        Id as UserId,
        DisplayName,
        CreationDate,
        Reputation,
        cast(CreationDate as date) as RepDate
    from Users
    where CreationDate >= '2010-01-01'
    union all
    select
        u.Id,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        date(r.RepDate, '+1 day')
    from Users u
    join RecursiveUserReputationGrowth r on u.Id = r.UserId
    where r.RepDate < date('now')
),
BadgeCountByUser as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        count(distinct case when TagBased = 1 then Name end) as DistinctTagBadges
    from Badges
    group by UserId
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.OwnerUserId,
        q.CreationDate,
        count(a.Id) as TotalAnswers,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        max(coalesce(a.Score,0)) as MaxAnswerScore,
        sum(case when a.OwnerUserId = q.OwnerUserId then 1 else 0 end) as AnswersByAuthor
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.OwnerUserId, q.CreationDate
),
TopQuestionComments as (
    select
        c.PostId,
        c.Id as CommentId,
        c.Score,
        c.Text,
        row_number() over (partition by c.PostId order by c.Score desc nulls last, c.CreationDate) as rn
    from Comments c
    join Posts p on p.Id = c.PostId and p.PostTypeId = 1
    where c.Score is not null
),
CloseVotesDetails as (
    select
        ph.PostId,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVotes,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenVotes,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as LastCloseVoteDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenVoteDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
UserReputationPercentiles as (
    select
        UserId,
        Reputation,
        percentile_cont(0.5) within group (order by Reputation) over () as MedianReputation,
        percentile_cont(0.9) within group (order by Reputation) over () as NinetyPctReputation
    from Users
),
UserParticipationSummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        b.DistinctTagBadges,
        coalesce(sum(vp.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vp.DownVotes),0) as TotalDownVotes,
        coalesce(sum(vp.Views),0) as TotalViews,
        coalesce(sum(qas.TotalAnswers),0) as TotalAnswers,
        coalesce(sum(qas.AnswersByAuthor),0) as AnswersAuthoredOnOwnQuestions
    from Users u
    left join BadgeCountByUser b on b.UserId = u.Id
    left join (
        select OwnerUserId, 
            sum(case when PostTypeId = 1 then 1 else 0 end) as Views,
            sum(case when PostTypeId = 2 then 0 else 0 end) as UpVotes,
            sum(case when PostTypeId = 2 then 0 else 0 end) as DownVotes
        from Posts
        group by OwnerUserId
    ) vp on vp.OwnerUserId = u.Id
    left join QuestionAnswerStats qas on qas.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, b.GoldBadges, b.SilverBadges, b.BronzeBadges, b.DistinctTagBadges
)
select
    p.Id as PostId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    u.DisplayName as OwnerName,
    case 
      when p.AcceptedAnswerId is not null then 'Accepted'
      else 'Not Accepted' 
    end as AcceptanceStatus,
    qas.TotalAnswers,
    qas.AvgAnswerScore,
    qas.MaxAnswerScore,
    qas.AnswersByAuthor,
    cv.CloseVotes,
    cv.ReopenVotes,
    cv.LastCloseVoteDate,
    cv.LastReopenVoteDate,
    crt.Name as LastCloseReason,
    tc.CommentId as TopCommentId,
    tc.Score as TopCommentScore,
    substring(tc.Text from 1 for 80) as TopCommentSnippet,
    urs.GoldBadges,
    urs.SilverBadges,
    urs.BronzeBadges,
    urs.DistinctTagBadges,
    urs.TotalUpVotes,
    urs.TotalDownVotes,
    urs.TotalViews,
    urs.TotalAnswers,
    urs.AnswersAuthoredOnOwnQuestions,
    urp.MedianReputation,
    urp.NinetyPctReputation
from Posts p
left join Users u on u.Id = p.OwnerUserId
left join QuestionAnswerStats qas on qas.QuestionId = p.Id
left join CloseVotesDetails cv on cv.PostId = p.Id
left join CloseReasonTypes crt on crt.Id = cv.LastCloseReasonId::int
left join TopQuestionComments tc on tc.PostId = p.Id and tc.rn = 1
left join UserParticipationSummary urs on urs.UserId = p.OwnerUserId
left join UserReputationPercentiles urp on urp.UserId = p.OwnerUserId
where p.PostTypeId = 1
  and p.CreationDate >= '2018-01-01'
  and (
       (p.Score > 5 and qas.TotalAnswers > 2)
       or
       (cv.CloseVotes > 3 and cv.ReopenVotes = 0)
      )
order by p.Score desc, qas.TotalAnswers desc, p.ViewCount desc
limit 100;