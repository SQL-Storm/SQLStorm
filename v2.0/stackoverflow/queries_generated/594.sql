-- {"query": "594.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3152} 
with
q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    case when p.ClosedDate is null then 0 else 1 end as IsClosed
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select
    pa.ParentId as QuestionId,
    pa.Id as AnswerId,
    pa.OwnerUserId as AnswerOwnerId,
    pa.Score as AnswerScore,
    pa.CreationDate as AnswerCreationDate
  from Posts pa
  where pa.PostTypeId = 2
),
acc as (
  select
    q.QuestionId,
    q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1
    and q.AcceptedAnswerId is not null
),
u_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.Views as ProfileViews,
    u.UpVotes,
    u.DownVotes,
    date_part('year', age(current_timestamp, u.CreationDate))::int as AccountAgeYears
  from Users u
),
cmt as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(coalesce(c.Score,0)) as CommentScoreSum,
    max(c.CreationDate) as LastCommentDate
  from Comments c
  group by c.PostId
),
v_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpvoteCount,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownvoteCount,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCountVotes,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal
  from Votes v
  group by v.PostId
),
ph_close as (
  select
    ph.PostId,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstCloseDate,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenDate,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
    count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
    count(*) filter (where ph.PostHistoryTypeId in (12,13)) as DeleteUndeleteEvents,
    max(ph.CreationDate) as LastPHEventDate,
    max(ph.Comment) filter (where ph.PostHistoryTypeId = 10) as LastCloseReasonRaw
  from PostHistory ph
  group by ph.PostId
),
pl as (
  select
    pl.PostId,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedOutCount,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateOfCount
  from PostLinks pl
  group by pl.PostId
),
t as (
  select
    p.Id as QuestionId,
    unnest(string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><')) as TagName
  from Posts p
  where p.PostTypeId = 1
    and p.Tags is not null
),
tag_rank as (
  select
    t.QuestionId,
    t.TagName,
    row_number() over (partition by t.QuestionId order by t.TagName) as TagOrdinal
  from t
),
top3_tags as (
  select
    tr.QuestionId,
    string_agg(tr.TagName, '|' order by tr.TagOrdinal) filter (where tr.TagOrdinal <= 3) as Top3Tags
  from tag_rank tr
  group by tr.QuestionId
),
answer_stats as (
  select
    a.QuestionId,
    count(*) as TotalAnswers,
    sum(case when a.AnswerScore > 0 then 1 else 0 end) as PositiveAnswers,
    max(a.AnswerScore) as MaxAnswerScore,
    min(a.AnswerScore) as MinAnswerScore,
    avg(a.AnswerScore::numeric) as AvgAnswerScore,
    max(a.AnswerCreationDate) as LastAnswerDate
  from a
  group by a.QuestionId
),
first_answer as (
  select distinct on (a.QuestionId)
    a.QuestionId,
    a.AnswerId,
    a.AnswerOwnerId,
    a.AnswerScore,
    a.AnswerCreationDate
  from a
  order by a.QuestionId, a.AnswerCreationDate asc, a.AnswerId asc
),
user_activity as (
  select
    p.OwnerUserId as UserId,
    count(*) filter (where p.PostTypeId = 1) as QuestionsAuthored,
    count(*) filter (where p.PostTypeId = 2) as AnswersAuthored,
    max(p.LastActivityDate) as LastPostActivity
  from Posts p
  where p.OwnerUserId is not null
  group by p.OwnerUserId
),
badge_counts as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    count(*) as TotalBadges,
    sum(case when b.TagBased = 1 then 1 else 0 end) as TagBadges
  from Badges b
  group by b.UserId
),
q_enriched as (
  select
    q.QuestionId,
    q.Title,
    q.CreationDate as QuestionCreationDate,
    q.Score as QuestionScore,
    q.ViewCount,
    q.OwnerUserId,
    q.AnswerCount,
    q.IsClosed,
    coalesce(v.UpvoteCount,0) as QUpvotes,
    coalesce(v.DownvoteCount,0) as QDownvotes,
    coalesce(v.FavoriteCountVotes,0) as QFavoriteVotes,
    coalesce(v.BountyTotal,0) as QBountyTotal,
    coalesce(c.CommentCount,0) as QCommentCount,
    coalesce(c.CommentScoreSum,0) as QCommentScoreSum,
    c.LastCommentDate as QLastCommentDate,
    ph.FirstCloseDate,
    ph.LastReopenDate,
    coalesce(ph.CloseEvents,0) as CloseEvents,
    coalesce(ph.ReopenEvents,0) as ReopenEvents,
    coalesce(ph.DeleteUndeleteEvents,0) as DeleteUndeleteEvents,
    ph.LastPHEventDate,
    ph.LastCloseReasonRaw,
    pl.LinkedOutCount,
    pl.DuplicateOfCount
  from q
  left join v_agg v on v.PostId = q.QuestionId
  left join cmt c on c.PostId = q.QuestionId
  left join ph_close ph on ph.PostId = q.QuestionId
  left join pl on pl.PostId = q.QuestionId
),
quality_scores as (
  select
    qe.QuestionId,
    (
      coalesce(qe.QUpvotes,0) * 2
      - coalesce(qe.QDownvotes,0)
      + coalesce(qe.QCommentScoreSum,0) * 0.2
      + coalesce(as2.MaxAnswerScore,0) * 0.5
      + least(coalesce(qe.ViewCount,0)/1000.0, 50)
      + case when qe.IsClosed = 1 then -5 else 0 end
      + case when qe.DuplicateOfCount > 0 then -10 else 0 end
      + case when qe.QBountyTotal > 0 then 5 else 0 end
    )::numeric(18,4) as QualityScore
  from q_enriched qe
  left join answer_stats as2 on as2.QuestionId = qe.QuestionId
),
owner_enriched as (
  select
    qe.QuestionId,
    u.Id as OwnerUserId,
    u.DisplayName,
    us.Reputation,
    us.AccountAgeYears,
    coalesce(ua.QuestionsAuthored,0) as QuestionsAuthored,
    coalesce(ua.AnswersAuthored,0) as AnswersAuthored,
    ua.LastPostActivity,
    coalesce(bc.GoldBadges,0) as GoldBadges,
    coalesce(bc.SilverBadges,0) as SilverBadges,
    coalesce(bc.BronzeBadges,0) as BronzeBadges,
    coalesce(bc.TotalBadges,0) as TotalBadges
  from q_enriched qe
  left join Users u on u.Id = qe.OwnerUserId
  left join u_stats us on us.UserId = u.Id
  left join user_activity ua on ua.UserId = u.Id
  left join badge_counts bc on bc.UserId = u.Id
),
accepted_answer_delta as (
  select
    q.QuestionId,
    a1.AnswerCreationDate as FirstAnswerDate,
    aa.CreationDate as AcceptedAnswerCreationDate,
    extract(epoch from (aa.CreationDate - q.CreationDate))/3600.0 as HoursToAcceptedFromQuestion,
    extract(epoch from (aa.CreationDate - a1.AnswerCreationDate))/3600.0 as HoursFromFirstAnswerToAccepted
  from Posts q
  join acc ac on ac.QuestionId = q.Id
  join Posts aa on aa.Id = ac.AcceptedAnswerId
  left join first_answer a1 on a1.QuestionId = q.Id
  where q.PostTypeId = 1
),
ranked_questions as (
  select
    qe.*,
    os.DisplayName as OwnerDisplayName,
    os.Reputation as OwnerReputation,
    os.AccountAgeYears,
    os.QuestionsAuthored,
    os.AnswersAuthored,
    os.LastPostActivity,
    coalesce(t3.Top3Tags, '') as Top3Tags,
    coalesce(as2.TotalAnswers,0) as TotalAnswers,
    coalesce(as2.PositiveAnswers,0) as PositiveAnswers,
    as2.MaxAnswerScore,
    as2.MinAnswerScore,
    as2.AvgAnswerScore,
    as2.LastAnswerDate,
    ql.QualityScore,
    aad.HoursToAcceptedFromQuestion,
    aad.HoursFromFirstAnswerToAccepted,
    row_number() over (
      order by
        ql.QualityScore desc nulls last,
        qe.ViewCount desc nulls last,
        qe.QuestionCreationDate desc nulls last
    ) as QualityRank
  from q_enriched qe
  left join owner_enriched os on os.QuestionId = qe.QuestionId
  left join top3_tags t3 on t3.QuestionId = qe.QuestionId
  left join answer_stats as2 on as2.QuestionId = qe.QuestionId
  left join quality_scores ql on ql.QuestionId = qe.QuestionId
  left join accepted_answer_delta aad on aad.QuestionId = qe.QuestionId
),
dup_clusters as (
  select
    qid,
    min(qid) over (partition by cluster_id) as cluster_root,
    cluster_id
  from (
    select
      x.QuestionId as qid,
      coalesce(min(x.RelatedPostId) over (partition by x.RelatedPostId), x.RelatedPostId) as cluster_id
    from (
      select p.Id as QuestionId, pl.RelatedPostId
      from Posts p
      left join PostLinks pl
        on pl.PostId = p.Id and pl.LinkTypeId = 3
      where p.PostTypeId = 1
    ) x
  ) y
),
final_set as (
  select
    rq.QuestionId,
    rq.Title,
    rq.OwnerDisplayName,
    rq.OwnerReputation,
    rq.AccountAgeYears,
    rq.QuestionsAuthored,
    rq.AnswersAuthored,
    rq.Top3Tags,
    rq.QuestionCreationDate,
    rq.QuestionScore,
    rq.ViewCount,
    rq.AnswerCount,
    rq.TotalAnswers,
    rq.PositiveAnswers,
    rq.MaxAnswerScore,
    rq.MinAnswerScore,
    rq.AvgAnswerScore,
    rq.LastAnswerDate,
    rq.QUpvotes,
    rq.QDownvotes,
    rq.QFavoriteVotes,
    rq.QBountyTotal,
    rq.QCommentCount,
    rq.QCommentScoreSum,
    rq.QLastCommentDate,
    rq.FirstCloseDate,
    rq.LastReopenDate,
    rq.CloseEvents,
    rq.ReopenEvents,
    rq.DeleteUndeleteEvents,
    rq.LastPHEventDate,
    rq.LastCloseReasonRaw,
    rq.LinkedOutCount,
    rq.DuplicateOfCount,
    rq.QualityScore,
    rq.HoursToAcceptedFromQuestion,
    rq.HoursFromFirstAnswerToAccepted,
    rq.QualityRank,
    dc.cluster_root as DuplicateClusterRoot
  from ranked_questions rq
  left join dup_clusters dc on dc.qid = rq.QuestionId
),
recent_vs_legacy as (
  select
    f.*,
    case when f.QuestionCreationDate >= current_timestamp - interval '3 years' then 'recent' else 'legacy' end as AgeBucket
  from final_set f
),
bucket_stats as (
  select
    AgeBucket,
    count(*) as Questions,
    avg(QualityScore) as AvgQuality,
    percentile_cont(0.5) within group (order by QualityScore) as MedianQuality,
    avg(ViewCount::numeric) as AvgViews,
    avg(coalesce(TotalAnswers,0)) as AvgAnswers
  from recent_vs_legacy
  group by AgeBucket
)
select
  rvl.*,
  bs.AvgQuality as BucketAvgQuality,
  bs.MedianQuality as BucketMedianQuality,
  bs.AvgViews as BucketAvgViews,
  bs.AvgAnswers as BucketAvgAnswers
from recent_vs_legacy rvl
left join bucket_stats bs
  on bs.AgeBucket = rvl.AgeBucket
where (
    rvl.QualityScore >= (
      select avg(QualityScore) + stddev_pop(QualityScore)
      from final_set
    )
    or rvl.DuplicateOfCount > 0
  )
and coalesce(rvl.OwnerReputation, 0) >= 1
order by
  rvl.QualityRank asc nulls last,
  rvl.ViewCount desc nulls last
limit 250;