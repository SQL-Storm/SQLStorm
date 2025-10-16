-- {"query": "7020.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2789} 
with
-- recent active questions with tag array and derived metrics
RecentQuestions as (
  select
    p.Id,
    p.Title,
    p.CreationDate,
    p.OwnerUserId,
    coalesce(p.Score,0) as Score,
    coalesce(p.ViewCount,0) as ViewCount,
    coalesce(p.AnswerCount,0) as AnswerCount,
    p.Tags,
    -- split tags from format '<tag1><tag2>' into array (Postgres syntax assumed)
    case when p.Tags is null then array[]::text[] else string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') end as TagArray
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= now() - interval '365 days'
),
-- aggregate badges per user (counts, recent)
UserBadges as (
  select
    b.UserId,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges,
    min(b.Date) as FirstBadgeDate,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
-- votes summary per post (including window to get latest 3 voters per post)
PostVotes as (
  select
    v.PostId,
    count(*) filter (where v.VoteTypeId = 2) as UpVotes,
    count(*) filter (where v.VoteTypeId = 3) as DownVotes,
    count(*) filter (where v.VoteTypeId = 5) as Favorites,
    count(*) as TotalVotes
  from Votes v
  group by v.PostId
),
RecentVoters as (
  select *
  from (
    select
      v.PostId,
      v.UserId,
      v.VoteTypeId,
      v.CreationDate,
      row_number() over (partition by v.PostId order by v.CreationDate desc, v.Id desc) as rn
    from Votes v
    where v.UserId is not null
  ) t
  where t.rn <= 3
),
-- comment stats (including correlated subquery to find longest comment text per post)
PostComments as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(coalesce(c.Score,0)) as CommentScoreSum,
    max(char_length(c.Text)) as LongestCommentLen,
    -- correlated subquery to fetch the text of the longest comment (ties broken by earliest CreationDate)
    (select c2.Text
     from Comments c2
     where c2.PostId = min(c.PostId) over ()
       and c2.PostId = c.PostId
     order by char_length(c2.Text) desc, c2.CreationDate asc
     limit 1) as ExampleLongestComment
  from Comments c
  group by c.PostId
),
-- compute for each question a scorecard including whether it has an accepted answer, number of duplicates linked, and if it was migrated
QuestionEdges as (
  select
    q.Id as QuestionId,
    q.AcceptedAnswerId,
    coalesce(plink.DuplicatesOut,0) as DuplicatesOut,
    coalesce(plink.LinksOut,0) as LinksOut,
    case when exists (
      select 1 from PostHistory ph
      where ph.PostId = q.Id and ph.PostHistoryTypeId in (17,35,36)
      ) then true else false end as EverMigrated,
    -- last close reason if closed (from PostHistory with type 10)
    (select crt.Name
     from PostHistory ph2
     left join CloseReasonTypes crt on crt.Id = (ph2.Comment::int) -- older schemas stored close reason id in Comment
     where ph2.PostId = q.Id and ph2.PostHistoryTypeId = 10
     order by ph2.CreationDate desc
     limit 1) as LastCloseReason
  from RecentQuestions q
  left join (
    select
      pl.PostId,
      sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicatesOut,
      sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinksOut
    from PostLinks pl
    group by pl.PostId
  ) plink on plink.PostId = q.Id
),
-- compute per-user activity windows and ranking
UserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(ub.GoldBadges,0) as GoldBadges,
    coalesce(ub.SilverBadges,0) as SilverBadges,
    coalesce(ub.BronzeBadges,0) as BronzeBadges,
    -- number of questions and answers in last year (using Posts)
    coalesce(qc.QCount,0) as QuestionsLastYear,
    coalesce(ac.ACount,0) as AnswersLastYear,
    -- active score heuristic
    (coalesce(qc.QCount,0) * 3 + coalesce(ac.ACount,0) * 5 + coalesce(ub.GoldBadges,0) * 10 + coalesce(ub.SilverBadges,0) * 3) as ActiveScore
  from Users u
  left join UserBadges ub on ub.UserId = u.Id
  left join (
    select p.OwnerUserId, count(*) as QCount
    from Posts p
    where p.PostTypeId = 1 and p.CreationDate >= now() - interval '365 days'
    group by p.OwnerUserId
  ) qc on qc.OwnerUserId = u.Id
  left join (
    select p.OwnerUserId, count(*) as ACount
    from Posts p
    where p.PostTypeId = 2 and p.CreationDate >= now() - interval '365 days'
    group by p.OwnerUserId
  ) ac on ac.OwnerUserId = u.Id
),
TopUsers as (
  select *,
    row_number() over (order by ActiveScore desc, Reputation desc nulls last) as ActiveRank
  from UserActivity
),
-- expand tags into rows for tag-level aggregation (unnest)
QuestionTags as (
  select
    q.Id as QuestionId,
    tag
  from RecentQuestions q
  cross join lateral unnest(q.TagArray) as t(tag)
),
TagMetrics as (
  select
    qt.tag,
    count(distinct qt.QuestionId) as QuestionsWithTag,
    avg(rq.Score) filter (where rq.Score is not null) as AvgScore,
    sum(coalesce(pv.UpVotes,0)) as TagUpVotes,
    sum(coalesce(pv.DownVotes,0)) as TagDownVotes
  from QuestionTags qt
  left join RecentQuestions rq on rq.Id = qt.QuestionId
  left join PostVotes pv on pv.PostId = qt.QuestionId
  group by qt.tag
),
-- heavy join that brings many elements together for benchmarking
QuestionFull as (
  select
    rq.Id,
    rq.Title,
    rq.CreationDate,
    rq.OwnerUserId,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    qb.GoldBadges,
    qb.SilverBadges,
    qb.BronzeBadges,
    qedge.AcceptedAnswerId,
    qedge.DuplicatesOut,
    qedge.LinksOut,
    qedge.EverMigrated,
    qedge.LastCloseReason,
    pv.UpVotes,
    pv.DownVotes,
    pv.Favorites,
    pc.CommentCount,
    pc.CommentScoreSum,
    pc.LongestCommentLen,
    pc.ExampleLongestComment,
    array_agg(distinct qt.tag order by qt.tag) filter (where qt.tag is not null) as Tags,
    -- windowed popularity metrics
    row_number() over (partition by 1 order by rq.ViewCount desc, rq.Score desc) as GlobalHotRank,
    dense_rank() over (partition by 1 order by (coalesce(pv.UpVotes,0)-coalesce(pv.DownVotes,0)) desc) as VoteRank
  from RecentQuestions rq
  left join Users u on u.Id = rq.OwnerUserId
  left join UserBadges qb on qb.UserId = rq.OwnerUserId
  left join QuestionEdges qedge on qedge.QuestionId = rq.Id
  left join PostVotes pv on pv.PostId = rq.Id
  left join PostComments pc on pc.PostId = rq.Id
  left join QuestionTags qt on qt.QuestionId = rq.Id
  group by
    rq.Id, rq.Title, rq.CreationDate, rq.OwnerUserId, u.DisplayName, u.Reputation,
    qb.GoldBadges, qb.SilverBadges, qb.BronzeBadges,
    qedge.AcceptedAnswerId, qedge.DuplicatesOut, qedge.LinksOut, qedge.EverMigrated, qedge.LastCloseReason,
    pv.UpVotes, pv.DownVotes, pv.Favorites,
    pc.CommentCount, pc.CommentScoreSum, pc.LongestCommentLen, pc.ExampleLongestComment,
    rq.ViewCount, rq.Score
)
select
  qf.Id,
  qf.Title,
  qf.CreationDate,
  qf.OwnerUserId,
  coalesce(qf.OwnerName, 'unknown') as OwnerDisplay,
  qf.OwnerReputation,
  qf.GoldBadges,
  qf.SilverBadges,
  qf.BronzeBadges,
  qf.Tags,
  qf.UpVotes,
  qf.DownVotes,
  qf.Favorites,
  qf.CommentCount,
  qf.CommentScoreSum,
  qf.LongestCommentLen,
  -- derived engagement metric with NULL-aware math and string formatting
  (coalesce(qf.UpVotes,0) * 2 + coalesce(qf.Favorites,0) * 3 + coalesce(qf.CommentCount,0) * 1) /
    nullif(1 + least(1000, greatest(1, coalesce((qf.OwnerReputation),0))), 0) as EngagementPerReputation,
  -- friendly indicators
  case when qf.AcceptedAnswerId is not null then true else false end as HasAcceptedAnswer,
  qf.DuplicatesOut,
  qf.LinksOut,
  qf.EverMigrated,
  qf.LastCloseReason,
  qf.GlobalHotRank,
  qf.VoteRank,
  -- correlated subquery: top 3 recent voters concatenated
  (select string_agg(coalesce(u2.DisplayName, 'user_' || v.UserId::text) || ':' || vt.Name, ', ')
   from (
     select rv.PostId, rv.UserId, rv.VoteTypeId, rv.CreationDate
     from RecentVoters rv
     where rv.PostId = qf.Id
     order by rv.CreationDate desc
     limit 3
   ) v
   left join Users u2 on u2.Id = v.UserId
   left join VoteTypes vt on vt.Id = v.VoteTypeId
  ) as RecentVotersSample,
  -- list of related top tags (set operator example: intersection between this question's tags and top 5 overall tags)
  (select array_agg(t.tag order by t.QuestionsWithTag desc)
   from TagMetrics t
   where t.tag = any(qf.Tags)
   order by t.QuestionsWithTag desc
   limit 5
  ) as TopRelatedTags,
  -- an artificial heavy expression to stress CPU: nested COALESCE, CASE, division, modulo, power, and string manipulation
  substr(
    md5(
      coalesce(qf.Title, '') || '|' ||
      coalesce(qf.OwnerDisplay, '') || '|' ||
      coalesce((qf.UpVotes - qf.DownVotes)::text, '0') || '|' ||
      coalesce(qf.Tags::text, '{}')
    ),
    1, 16
  ) || '-' ||
  (case when coalesce(qf.ViewCount,0) = 0 then 'NOVIEWS' else ( (power(coalesce(qf.Score,0)::numeric,2) + coalesce(qf.UpVotes,0) - coalesce(qf.DownVotes,0))::bigint % 100000 )::text end) as SyntheticFingerprint
from QuestionFull qf
-- filter to non-trivial posts and order to exercise sorting
where (coalesce(qf.UpVotes,0) + coalesce(qf.DownVotes,0) + coalesce(qf.CommentCount,0)) > 0
  and (qf.OwnerReputation is null or qf.OwnerReputation >= 0)
order by qf.GlobalHotRank asc, qf.VoteRank asc, qf.CreationDate desc
limit 200;