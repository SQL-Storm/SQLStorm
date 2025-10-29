-- {"query": "579.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2860} 
with
q as (
  select
    p.Id as QuestionId,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    count(a.Id) filter (where a.PostTypeId = 2) as ActualAnswers,
    max(a.Score) filter (where a.PostTypeId = 2) as MaxAnswerScore,
    count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesOnQ,
    count(v2.Id) filter (where v2.VoteTypeId = 3) as DownVotesOnQ
  from Posts p
  left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
  left join Votes v on v.PostId = p.Id
  left join Votes v2 on v2.PostId = p.Id
  where p.PostTypeId = 1
    and p.CreationDate >= (select min(CreationDate) from Posts where PostTypeId = 1)
  group by p.Id, p.Title, p.CreationDate, p.OwnerUserId, p.Score, p.ViewCount, p.Tags, p.AnswerCount
),
answers as (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.Score,
    a.CreationDate,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_by_score,
    rank() over (partition by a.ParentId order by a.CreationDate asc) as first_answer_rank,
    sum(a.Score) over (partition by a.ParentId) as sum_answer_scores
  from Posts a
  where a.PostTypeId = 2
),
accepted as (
  select
    q.QuestionId,
    p2.Id as AcceptedAnswerId,
    p2.OwnerUserId as AcceptedOwnerUserId,
    p2.Score as AcceptedScore,
    p2.CreationDate as AcceptedCreationDate
  from Posts p
  join Posts q on q.Id = p.Id and q.PostTypeId = 1
  left join Posts p2 on p2.Id = p.AcceptedAnswerId
),
tag_split as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q
),
tag_stats as (
  select
    ts.tag,
    count(*) as tag_q_cnt,
    avg(q.Score) as tag_avg_q_score,
    percentile_cont(0.9) within group (order by q.ViewCount) as p90_views
  from tag_split ts
  join q on q.QuestionId = ts.QuestionId
  group by ts.tag
),
user_stats as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate as UserCreationDate,
    coalesce(sum(case when p.PostTypeId = 1 then 1 else 0 end),0) as QuestionsAuthored,
    coalesce(sum(case when p.PostTypeId = 2 then 1 else 0 end),0) as AnswersAuthored,
    coalesce(sum(p.Score) filter (where p.PostTypeId = 2),0) as TotalAnswerScore,
    count(distinct b.Name) as DistinctBadges,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
    max(b.Date) as LastBadgeDate
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
q_activity as (
  select
    ph.PostId as QuestionId,
    count(*) filter (where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35,36)) as ModActionCount,
    count(*) filter (where ph.PostHistoryTypeId in (10)) as CloseEvents,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10)) as FirstCloseDate,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (11)) as LastReopenDate,
    count(*) filter (where ph.PostHistoryTypeId = 24) as SuggestedEditsApplied
  from PostHistory ph
  group by ph.PostId
),
dup_clusters as (
  select
    pl.RelatedPostId as CanonicalId,
    count(*) filter (where pl.LinkTypeId = 3) as DupCount,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedCount
  from PostLinks pl
  group by pl.RelatedPostId
),
comment_agg as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(c.Score) as CommentScoreSum,
    max(c.CreationDate) as LastCommentDate,
    string_agg(distinct coalesce(trim(c.UserDisplayName), cast(c.UserId as varchar)), ', ' order by coalesce(trim(c.UserDisplayName), cast(c.UserId as varchar)) asc) as Commenters
  from Comments c
  group by c.PostId
),
vote_agg as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes,
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
    min(v.CreationDate) filter (where v.VoteTypeId = 8) as FirstBountyStart
  from Votes v
  group by v.PostId
),
question_rank as (
  select
    q.QuestionId,
    q.Title,
    q.Score,
    q.ViewCount,
    q.CreationDate,
    dense_rank() over (order by q.Score desc nulls last, q.ViewCount desc nulls last) as dr_by_score_views,
    row_number() over (order by (q.Score * 1.0 / nullif(greatest(q.ViewCount,1),0)) desc) as rn_by_score_per_view
  from q
),
answer_choice as (
  select
    a.QuestionId,
    a.AnswerId as TopAnswerId,
    a.OwnerUserId as TopAnswerUserId,
    a.Score as TopAnswerScore,
    a.CreationDate as TopAnswerCreationDate
  from answers a
  where a.rn_by_score = 1
),
first_answer as (
  select
    a.QuestionId,
    a.AnswerId as FirstAnswerId,
    a.OwnerUserId as FirstAnswerUserId,
    a.Score as FirstAnswerScore,
    a.CreationDate as FirstAnswerCreationDate
  from answers a
  where a.first_answer_rank = 1
),
owner_or_anon as (
  select
    p.Id as QuestionId,
    case
      when p.OwnerUserId is null or p.OwnerUserId = -1 then 'anonymous'
      else 'user'
    end as OwnerType
  from Posts p
  where p.PostTypeId = 1
),
tag_quality as (
  select
    ts.tag,
    case
      when ts.tag_avg_q_score >= 10 then 'high'
      when ts.tag_avg_q_score >= 2 then 'medium'
      else 'low'
    end as quality_band
  from tag_stats ts
),
per_q_tag_features as (
  select
    ts.QuestionId,
    count(*) as TagCount,
    count(*) filter (where tq.quality_band = 'high') as HighQualityTagCount,
    max(ts.tag) filter (where tq.quality_band = 'high') as ExampleHighTag,
    bool_or(tq.quality_band = 'low') as HasLowQualityTag
  from tag_split ts
  left join tag_quality tq on tq.tag = ts.tag
  group by ts.QuestionId
),
posttype_map as (
  select Id, Name from PostTypes
),
final as (
  select
    q.QuestionId,
    coalesce(q.Title, '[no title]') as Title,
    q.Score,
    q.ViewCount,
    q.CreationDate,
    pt.Name as PostTypeName,
    u.DisplayName as OwnerName,
    us.Reputation as OwnerReputation,
    coalesce(us.QuestionsAuthored,0) as OwnerQuestions,
    coalesce(us.AnswersAuthored,0) as OwnerAnswers,
    coalesce(us.TotalAnswerScore,0) as OwnerTotalAnswerScore,
    us.DistinctBadges as OwnerDistinctBadges,
    q.AnswerCount as DeclaredAnswers,
    q.ActualAnswers,
    q.MaxAnswerScore,
    va.UpVotes as UpVotes,
    va.DownVotes as DownVotes,
    va.BountyTotal,
    va.FirstBountyStart,
    ca.CommentCount,
    ca.CommentScoreSum,
    ca.LastCommentDate,
    ca.Commenters,
    qa.ModActionCount,
    qa.CloseEvents,
    qa.FirstCloseDate,
    qa.LastReopenDate,
    qa.SuggestedEditsApplied,
    ac.AcceptedAnswerId,
    ac.AcceptedOwnerUserId,
    ac.AcceptedScore,
    ac.AcceptedCreationDate,
    an.TopAnswerId,
    an.TopAnswerUserId,
    an.TopAnswerScore,
    an.TopAnswerCreationDate,
    fa.FirstAnswerId,
    fa.FirstAnswerUserId,
    fa.FirstAnswerScore,
    fa.FirstAnswerCreationDate,
    pqtf.TagCount,
    pqtf.HighQualityTagCount,
    pqtf.ExampleHighTag,
    pqtf.HasLowQualityTag,
    oc.OwnerType,
    coalesce(dc.DupCount,0) as DuplicateCount,
    coalesce(dc.LinkedCount,0) as LinkedCount,
    qr.dr_by_score_views,
    qr.rn_by_score_per_view,
    case
      when coalesce(q.AnswerCount,0) <> q.ActualAnswers then 'mismatch'
      else 'match'
    end as AnswerCountConsistency,
    case
      when ac.AcceptedAnswerId is not null and an.TopAnswerId is not null and ac.AcceptedAnswerId <> an.TopAnswerId then 'accepted_not_top_scored'
      when ac.AcceptedAnswerId is null then 'no_accepted'
      else 'accepted_top_or_only'
    end as AcceptedVsTop,
    case
      when q.ViewCount is null or q.ViewCount = 0 then null
      else round((q.Score::numeric / nullif(q.ViewCount,0)) * 1000, 4)
    end as ScorePerKViews,
    case
      when q.Tags is null then 0
      else cardinality(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><'))
    end as TagCountRaw,
    case
      when position('java' in lower(coalesce(q.Title,''))) > 0 then 1
      when position('python' in lower(coalesce(q.Title,''))) > 0 then 1
      else 0
    end as TitleHasPopularLangKeyword,
    case
      when q.CreationDate >= now() - interval '365 days' then 'recent'
      when q.CreationDate >= now() - interval '1825 days' then 'mid'
      else 'old'
    end as AgeBucket
  from q
  left join Posts p on p.Id = q.QuestionId
  left join posttype_map pt on pt.Id = p.PostTypeId
  left join Users u on u.Id = p.OwnerUserId
  left join user_stats us on us.UserId = p.OwnerUserId
  left join vote_agg va on va.PostId = q.QuestionId
  left join comment_agg ca on ca.PostId = q.QuestionId
  left join q_activity qa on qa.QuestionId = q.QuestionId
  left join accepted ac on ac.QuestionId = q.QuestionId
  left join answer_choice an on an.QuestionId = q.QuestionId
  left join first_answer fa on fa.QuestionId = q.QuestionId
  left join per_q_tag_features pqtf on pqtf.QuestionId = q.QuestionId
  left join owner_or_anon oc on oc.QuestionId = q.QuestionId
  left join dup_clusters dc on dc.CanonicalId = q.QuestionId
  left join question_rank qr on qr.QuestionId = q.QuestionId
)
select *
from final
where
  (Score >= 0 or ViewCount >= 100)
  and (AcceptedVsTop <> 'no_accepted' or DuplicateCount > 0)
  and (HasLowQualityTag is distinct from true or HighQualityTagCount > 0)
order by
  ScorePerKViews desc nulls last,
  UpVotes desc nulls last,
  ViewCount desc nulls last,
  CreationDate desc
limit 500;