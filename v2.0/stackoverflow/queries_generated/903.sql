-- {"query": "903.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2699} 
with
q as (
  select p.Id as QuestionId,
         p.CreationDate as QuestionCreation,
         p.OwnerUserId as QuestionOwnerId,
         p.Score as QuestionScore,
         p.ViewCount,
         p.Tags,
         p.AcceptedAnswerId,
         coalesce(nullif(trim(p.Title), ''), '[no title]') as NormalizedTitle
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswerOwnerId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreation
  from Posts a
  where a.PostTypeId = 2
),
user_activity as (
  select u.Id as UserId,
         u.Reputation,
         u.CreationDate as UserCreated,
         u.LastAccessDate as UserLastAccess,
         u.UpVotes,
         u.DownVotes,
         u.Views as ProfileViews,
         sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotesCast,
         count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
         count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
         count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges
  from Users u
  left join Votes v on v.UserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
),
q_answer_stats as (
  select
    q.QuestionId,
    count(a.AnswerId) as TotalAnswers,
    sum(case when a.AnswerId = q.AcceptedAnswerId then 1 else 0 end) as HasAccepted,
    avg(a.AnswerScore::numeric) as AvgAnswerScore,
    max(a.AnswerScore) as MaxAnswerScore,
    min(a.AnswerScore) as MinAnswerScore,
    percentile_cont(0.5) within group (order by a.AnswerScore) as MedianAnswerScore,
    min(a.AnswerCreation) as FirstAnswerAt,
    max(a.AnswerCreation) as LastAnswerAt
  from q
  left join a on a.QuestionId = q.QuestionId
  group by q.QuestionId
),
q_comment_stats as (
  select
    p.Id as QuestionId,
    count(c.Id) filter (where c.Id is not null) as CommentCount,
    coalesce(sum(c.Score), 0) as CommentScoreSum,
    max(c.Score) as MaxCommentScore
  from Posts p
  left join Comments c on c.PostId = p.Id
  where p.PostTypeId = 1
  group by p.Id
),
tag_expansion as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q
  where q.Tags is not null and q.Tags like '<%>'
),
top_tags as (
  select tag,
         count(*) as TagUsage,
         rank() over (order by count(*) desc, tag asc) as tag_rank
  from tag_expansion
  group by tag
),
q_tag_profile as (
  select te.QuestionId,
         count(*) as TagCount,
         sum(case when tt.tag_rank <= 100 then 1 else 0 end) as Top100TagHits,
         string_agg(te.tag, ',' order by te.tag) as TagListCSV
  from tag_expansion te
  left join top_tags tt on tt.tag = te.tag
  group by te.QuestionId
),
close_events as (
  select ph.PostId,
         min(ph.CreationDate) as FirstCloseDate,
         max(ph.CreationDate) as LastCloseDate,
         count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesEvents,
         max(case when ph.PostHistoryTypeId = 10 then nullif(ph.Comment, '') end) as AnyCloseReasonIdText
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11)
  group by ph.PostId
),
dup_links as (
  select pl.PostId as QuestionId,
         count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
         count(*) filter (where pl.LinkTypeId = 1) as RelatedLinks
  from PostLinks pl
  group by pl.PostId
),
question_quality as (
  select
    q.QuestionId,
    q.QuestionCreation,
    q.QuestionOwnerId,
    q.QuestionScore,
    q.ViewCount,
    qa.TotalAnswers,
    qa.HasAccepted,
    qa.AvgAnswerScore,
    qa.FirstAnswerAt,
    qc.CommentCount,
    qc.CommentScoreSum,
    qt.TagCount,
    qt.Top100TagHits,
    d.DuplicateLinks,
    d.RelatedLinks,
    c.FirstCloseDate,
    c.CloseVotesEvents,
    case
      when qa.TotalAnswers is null or qa.TotalAnswers = 0 then null
      else extract(epoch from (qa.FirstAnswerAt - q.QuestionCreation))/60.0
    end as MinutesToFirstAnswer,
    case
      when q.ViewCount is null or q.ViewCount = 0 then null
      else (q.QuestionScore::numeric / nullif(q.ViewCount,0))
    end as ScorePerView,
    case
      when qc.CommentCount > 0 then (qc.CommentScoreSum::numeric / qc.CommentCount)
      else null
    end as AvgCommentScore,
    case
      when qt.TagCount >= 5 then 'broad'
      when qt.TagCount between 3 and 4 then 'normal'
      when qt.TagCount between 1 and 2 then 'narrow'
      else 'untagged'
    end as TagBreadthBucket
  from q
  left join q_answer_stats qa on qa.QuestionId = q.QuestionId
  left join q_comment_stats qc on qc.QuestionId = q.QuestionId
  left join q_tag_profile qt on qt.QuestionId = q.QuestionId
  left join dup_links d on d.QuestionId = q.QuestionId
  left join close_events c on c.PostId = q.QuestionId
),
owner_rollup as (
  select
    qa.QuestionOwnerId as UserId,
    count(*) as QuestionsAuthored,
    sum(case when qa.HasAccepted = 1 then 1 else 0 end) as QuestionsWithAcceptedAnswer,
    avg(qa.QuestionScore::numeric) as AvgQuestionScore,
    percentile_cont(0.9) within group (order by qa.ViewCount) as P90Views
  from question_quality qa
  group by qa.QuestionOwnerId
),
recent_activity as (
  select
    p.OwnerUserId as UserId,
    count(*) filter (where p.PostTypeId = 1 and p.CreationDate >= now() - interval '365 days') as QuestionsLastYear,
    count(*) filter (where p.PostTypeId = 2 and p.CreationDate >= now() - interval '365 days') as AnswersLastYear,
    count(*) filter (where p.PostTypeId = 2 and p.Score >= 5 and p.CreationDate >= now() - interval '365 days') as GoodAnswersLastYear
  from Posts p
  group by p.OwnerUserId
),
user_score as (
  select
    ua.UserId,
    ua.Reputation,
    ua.UpVotes,
    ua.DownVotes,
    ua.NetVotesCast,
    coalesce(ua.GoldBadges,0) as GoldBadges,
    coalesce(ua.SilverBadges,0) as SilverBadges,
    coalesce(ua.BronzeBadges,0) as BronzeBadges,
    oru.QuestionsAuthored,
    oru.QuestionsWithAcceptedAnswer,
    oru.AvgQuestionScore,
    oru.P90Views,
    ra.QuestionsLastYear,
    ra.AnswersLastYear,
    ra.GoodAnswersLastYear,
    (
      coalesce(ua.Reputation,0)::numeric
      + 50 * coalesce(ra.GoodAnswersLastYear,0)
      + 10 * coalesce(oru.QuestionsWithAcceptedAnswer,0)
      + 5 * greatest(coalesce(ua.UpVotes,0) - coalesce(ua.DownVotes,0), 0)
      + 100 * coalesce(ua.GoldBadges,0) + 25 * coalesce(ua.SilverBadges,0) + 5 * coalesce(ua.BronzeBadges,0)
      + 0.1 * coalesce(oru.P90Views,0)
    ) as EngagementScore
  from user_activity ua
  left join owner_rollup oru on oru.UserId = ua.UserId
  left join recent_activity ra on ra.UserId = ua.UserId
),
question_ranked as (
  select
    qq.*,
    us.EngagementScore,
    row_number() over (
      partition by case when qq.TagBreadthBucket = 'untagged' then 'other' else qq.TagBreadthBucket end
      order by
        coalesce(qq.HasAccepted,0) desc,
        coalesce(qq.TotalAnswers,0) desc,
        coalesce(qq.ScorePerView, -1) desc,
        coalesce(qq.AvgCommentScore, -1) desc,
        coalesce(us.EngagementScore, -1) desc,
        qq.QuestionCreation desc
    ) as BucketRank
  from question_quality qq
  left join user_score us on us.UserId = qq.QuestionOwnerId
),
flagged_or_hot as (
  select
    q.QuestionId,
    max(case when ph.PostHistoryTypeId in (52,53) then 1 else 0 end) as HasHotEvent,
    count(*) filter (where ph.PostHistoryTypeId = 50) as CommunityBumps
  from q
  left join PostHistory ph on ph.PostId = q.QuestionId
  group by q.QuestionId
),
final_set as (
  select
    qr.QuestionId,
    qr.QuestionCreation,
    qr.QuestionOwnerId,
    qr.QuestionScore,
    qr.ViewCount,
    qr.TotalAnswers,
    qr.HasAccepted,
    qr.AvgAnswerScore,
    qr.MinutesToFirstAnswer,
    qr.ScorePerView,
    qr.AvgCommentScore,
    qr.TagBreadthBucket,
    qr.DuplicateLinks,
    qr.RelatedLinks,
    qr.FirstCloseDate,
    qr.CloseVotesEvents,
    qr.EngagementScore,
    fo.HasHotEvent,
    fo.CommunityBumps,
    qr.BucketRank
  from question_ranked qr
  left join flagged_or_hot fo on fo.QuestionId = qr.QuestionId
  where
    (
      qr.HasAccepted = 1
      or coalesce(qr.TotalAnswers,0) >= 3
      or (fo.HasHotEvent = 1 and coalesce(qr.ScorePerView,0) > 0)
    )
)
select *
from (
  select *, 'A:TopByBucket' as SourceSet
  from final_set
  where BucketRank <= 50
  union all
  select fs.*, 'B:HighEngagementButLowAnswers' as SourceSet
  from final_set fs
  where coalesce(fs.EngagementScore,0) > (
          select percentile_cont(0.8) within group (order by EngagementScore)
          from final_set
        )
    and coalesce(fs.TotalAnswers,0) <= 1
  union all
  select fs.*, 'C:LateFirstAnswer' as SourceSet
  from final_set fs
  where fs.MinutesToFirstAnswer > (
          select avg(MinutesToFirstAnswer) + stddev_pop(MinutesToFirstAnswer)
          from final_set
          where MinutesToFirstAnswer is not null
        )
) z
qualify row_number() over (
  partition by QuestionId
  order by
    case SourceSet when 'A:TopByBucket' then 1 when 'B:HighEngagementButLowAnswers' then 2 else 3 end,
    BucketRank nulls last
) = 1
order by
  coalesce(HasAccepted,0) desc,
  coalesce(TotalAnswers,0) desc,
  coalesce(ScorePerView,-1) desc,
  coalesce(EngagementScore,-1) desc,
  QuestionCreation desc
limit 500;