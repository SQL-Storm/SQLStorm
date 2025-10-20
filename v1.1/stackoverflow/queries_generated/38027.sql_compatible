with recent_questions as (
  select
    p.Id as QuestionId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.OwnerUserId,
    p.Tags,
    string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><') as tag_array
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '180 days' from Posts where PostTypeId = 1)
),
accepted_answers as (
  select
    q.QuestionId,
    a.Id as AcceptedAnswerId,
    a.Score as AcceptedAnswerScore,
    a.OwnerUserId as AcceptedAnswerOwnerId,
    a.CreationDate as AcceptedAnswerDate
  from recent_questions q
  join Posts qfull on qfull.Id = q.QuestionId
  join Posts a on a.Id = qfull.AcceptedAnswerId
),
answer_stats as (
  select
    q.QuestionId,
    count(a.Id) as AnswerCount,
    avg(a.Score) as AvgAnswerScore,
    max(a.Score) as MaxAnswerScore,
    min(a.Score) as MinAnswerScore
  from recent_questions q
  left join Posts a on a.ParentId = q.QuestionId and a.PostTypeId = 2
  group by q.QuestionId
),
question_vote_agg as (
  select
    v.PostId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
  from Votes v
  join recent_questions q on q.QuestionId = v.PostId
  group by v.PostId
),
first_comment_per_answer as (
  select distinct on (c.PostId)
    c.PostId as AnswerId,
    c.Id as FirstCommentId,
    c.CreationDate as FirstCommentDate
  from Comments c
  join Posts a on a.Id = c.PostId and a.PostTypeId = 2
  order by c.PostId, c.CreationDate asc, c.Id asc
),
time_to_first_answer as (
  select
    q.QuestionId,
    min(a.CreationDate) - min(q.CreationDate) as TimeToFirstAnswer
  from recent_questions q
  join Posts a on a.ParentId = q.QuestionId and a.PostTypeId = 2
  group by q.QuestionId, q.CreationDate
),
tag_expansion as (
  select
    q.QuestionId,
    unnest(q.tag_array) as tag
  from recent_questions q
),
top_tags as (
  select
    te.tag,
    count(*) as tag_usage
  from tag_expansion te
  group by te.tag
  order by count(*) desc
  limit 50
),
question_tag_rank as (
  select
    te.QuestionId,
    te.tag,
    row_number() over (partition by te.QuestionId order by tt.tag_usage desc, te.tag asc) as tag_rank
  from tag_expansion te
  join top_tags tt on tt.tag = te.tag
),
dupe_links as (
  select
    pl.PostId as QuestionId,
    count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateLinks
  from PostLinks pl
  join recent_questions q on q.QuestionId = pl.PostId
  group by pl.PostId
),
close_events as (
  select
    ph.PostId as QuestionId,
    min(ph.CreationDate) as FirstCloseDate,
    count(*) as CloseEventCount
  from PostHistory ph
  where ph.PostHistoryTypeId = 10
  group by ph.PostId
),
reopen_events as (
  select
    ph.PostId as QuestionId,
    min(ph.CreationDate) as FirstReopenDate,
    count(*) as ReopenEventCount
  from PostHistory ph
  where ph.PostHistoryTypeId = 11
  group by ph.PostId
),
hot_events as (
  select
    ph.PostId as QuestionId,
    min(case when ph.PostHistoryTypeId = 52 then ph.CreationDate end) as FirstHotDate,
    count(case when ph.PostHistoryTypeId = 52 then 1 end) as HotCount,
    count(case when ph.PostHistoryTypeId = 53 then 1 end) as RemovedHotCount
  from PostHistory ph
  group by ph.PostId
),
owner_activity as (
  select
    u.Id as OwnerUserId,
    u.Reputation,
    u.Views as ProfileViews,
    u.UpVotes as TotalUpVotes,
    u.DownVotes as TotalDownVotes,
    date_trunc('month', u.CreationDate) as UserCohort
  from Users u
),
answerer_badge_levels as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
answerer_vote_agg as (
  select
    a.OwnerUserId as AnswererId,
    count(case when v.VoteTypeId = 2 then 1 end) as AnswerUpVotes,
    count(case when v.VoteTypeId = 3 then 1 end) as AnswerDownVotes
  from Posts a
  left join Votes v on v.PostId = a.Id
  where a.PostTypeId = 2
  group by a.OwnerUserId
),
question_comment_agg as (
  select
    c.PostId as QuestionId,
    count(*) as CommentCount,
    avg(c.Score) as AvgCommentScore
  from Comments c
  join recent_questions q on q.QuestionId = c.PostId
  group by c.PostId
),
accepted_answer_first_comment_lag as (
  select
    aa.AcceptedAnswerId,
    fc.FirstCommentDate - aa.AcceptedAnswerDate as TimeToFirstCommentOnAccepted
  from accepted_answers aa
  left join first_comment_per_answer fc on fc.AnswerId = aa.AcceptedAnswerId
),
question_scores_z as (
  select
    q.QuestionId,
    q.Score,
    (q.Score - avg(q.Score) over ()) / nullif(stddev_pop(q.Score) over (), 0) as ScoreZ
  from recent_questions q
),
final as (
  select
    q.QuestionId,
    q.CreationDate,
    q.Score,
    qs.ScoreZ,
    q.ViewCount,
    qa.UpVotes as QUpVotes,
    qa.DownVotes as QDownVotes,
    qa.Favorites as QFavorites,
    asg.AnswerCount,
    asg.AvgAnswerScore,
    asg.MaxAnswerScore,
    asg.MinAnswerScore,
    ttl.TimeToFirstAnswer,
    aa.AcceptedAnswerId,
    aa.AcceptedAnswerScore,
    aowner.Reputation as AcceptedAnswerOwnerRep,
    aowner.UserCohort as AcceptedAnswerOwnerCohort,
    ab.BadgeLevelSummary,
    av.AnswerUpVotes,
    av.AnswerDownVotes,
    qc.CommentCount as QCommentCount,
    qc.AvgCommentScore as QAvgCommentScore,
    de.DuplicateLinks,
    ce.FirstCloseDate,
    ce.CloseEventCount,
    re.FirstReopenDate,
    re.ReopenEventCount,
    he.FirstHotDate,
    he.HotCount,
    he.RemovedHotCount,
    t1.tag as TopTag1,
    t2.tag as TopTag2,
    t3.tag as TopTag3,
    tafc.TimeToFirstCommentOnAccepted
  from recent_questions q
  left join question_vote_agg qa on qa.QuestionId = q.QuestionId
  left join answer_stats asg on asg.QuestionId = q.QuestionId
  left join time_to_first_answer ttl on ttl.QuestionId = q.QuestionId
  left join accepted_answers aa on aa.QuestionId = q.QuestionId
  left join owner_activity aowner on aowner.OwnerUserId = aa.AcceptedAnswerOwnerId
  left join (
    select
      ab.UserId,
      ('G:' || GoldCount || '|S:' || SilverCount || '|B:' || BronzeCount) as BadgeLevelSummary
    from answerer_badge_levels ab
  ) ab on ab.UserId = aa.AcceptedAnswerOwnerId
  left join answerer_vote_agg av on av.AnswererId = aa.AcceptedAnswerOwnerId
  left join question_comment_agg qc on qc.QuestionId = q.QuestionId
  left join dupe_links de on de.QuestionId = q.QuestionId
  left join close_events ce on ce.QuestionId = q.QuestionId
  left join reopen_events re on re.QuestionId = q.QuestionId
  left join hot_events he on he.QuestionId = q.QuestionId
  left join question_tag_rank t1 on t1.QuestionId = q.QuestionId and t1.tag_rank = 1
  left join question_tag_rank t2 on t2.QuestionId = q.QuestionId and t2.tag_rank = 2
  left join question_tag_rank t3 on t3.QuestionId = q.QuestionId and t3.tag_rank = 3
  left join accepted_answer_first_comment_lag tafc on tafc.AcceptedAnswerId = aa.AcceptedAnswerId
  left join question_scores_z qs on qs.QuestionId = q.QuestionId
)
select
  f.*,
  dense_rank() over (order by coalesce(f.HotCount,0) desc, coalesce(f.QUpVotes,0) - coalesce(f.QDownVotes,0) desc, coalesce(f.AnswerCount,0) desc, f.ViewCount desc, f.Score desc) as PopularityRank,
  row_number() over (partition by date_trunc('day', f.CreationDate) order by coalesce(f.QUpVotes,0) - coalesce(f.QDownVotes,0) desc, f.ViewCount desc) as DailyRank
from final f
where coalesce(f.AnswerCount,0) >= 1
order by PopularityRank, f.CreationDate desc
limit 500;