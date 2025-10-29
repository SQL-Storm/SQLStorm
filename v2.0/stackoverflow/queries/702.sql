-- {"query": "702.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3449}
with
q_posts as (
  select p.Id as QuestionId,
         p.OwnerUserId as QuestionOwnerId,
         p.CreationDate as QuestionCreated,
         p.Score as QuestionScore,
         p.ViewCount,
         p.Tags,
         p.Title,
         p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1
),
a_posts as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswerOwnerId,
         a.CreationDate as AnswerCreated,
         a.Score as AnswerScore
  from Posts a
  where a.PostTypeId = 2
),
user_activity as (
  select u.Id as UserId,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.Views as ProfileViews,
         coalesce(nullif(trim(u.Location), ''), 'Unknown') as LocationNorm,
         date_trunc('month', u.CreationDate) as UserCohortMonth,
         count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
         count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
         count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
         count(distinct b.Id) as TotalBadges
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, LocationNorm, UserCohortMonth
),
question_stats as (
  select q.QuestionId,
         q.QuestionOwnerId,
         q.QuestionCreated,
         q.QuestionScore,
         q.ViewCount,
         q.Title,
         q.Tags,
         q.AcceptedAnswerId,
         count(a.AnswerId) as AnswersCount,
         max(a.AnswerScore) as MaxAnswerScore,
         min(a.AnswerScore) as MinAnswerScore,
         avg(cast(a.AnswerScore as numeric)) as AvgAnswerScore
  from q_posts q
  left join a_posts a on a.QuestionId = q.QuestionId
  group by q.QuestionId, q.QuestionOwnerId, q.QuestionCreated, q.QuestionScore, q.ViewCount, q.Title, q.Tags, q.AcceptedAnswerId
),
comment_aggs as (
  select c.PostId,
         count(*) as CommentCount,
         sum(c.Score) as CommentScoreSum,
         avg(cast(c.Score as numeric)) as CommentScoreAvg,
         max(length(c.Text)) as MaxCommentLen,
         count(*) filter (where c.UserId is null) as AnonymousComments
  from Comments c
  group by c.PostId
),
vote_aggs as (
  select v.PostId,
         count(*) filter (where v.VoteTypeId = 2) as UpVotes,
         count(*) filter (where v.VoteTypeId = 3) as DownVotes,
         count(*) filter (where v.VoteTypeId = 5) as Favorites,
         count(*) filter (where v.VoteTypeId = 8) as BountyStarts,
         sum(v.BountyAmount) filter (where v.VoteTypeId in (8,9)) as BountyTotal
  from Votes v
  group by v.PostId
),
ph_close as (
  select ph.PostId,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (10,35)) as FirstCloseDate,
         max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (11)) as LastReopenDate,
         count(*) filter (where ph.PostHistoryTypeId in (10,35)) as CloseEvents,
         count(*) filter (where ph.PostHistoryTypeId in (11)) as ReopenEvents,
         count(*) filter (where ph.PostHistoryTypeId in (19)) as ProtectEvents
  from PostHistory ph
  group by ph.PostId
),
dup_links as (
  select pl.PostId as DuplicateOfId,
         count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
         count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks
  from PostLinks pl
  group by pl.PostId
),
tag_explode as (
  select q.QuestionId,
         unnest(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><')) as tag
  from q_posts q
  where q.Tags is not null and q.Tags like '<%>'
),
tag_hist as (
  select te.QuestionId,
         te.tag,
         row_number() over (partition by te.QuestionId order by te.tag) as tag_ordinal
  from tag_explode te
),
first_three_tags as (
  select th.QuestionId,
         string_agg(th.tag, ' ' order by th.tag_ordinal) filter (where th.tag_ordinal <= 3) as FirstThreeTags
  from tag_hist th
  group by th.QuestionId
),
owner_metrics as (
  select qs.QuestionId,
         ua.UserId,
         ua.Reputation,
         ua.TotalBadges,
         ua.GoldBadges,
         ua.SilverBadges,
         ua.BronzeBadges,
         ua.ProfileViews,
         ua.LocationNorm,
         ua.UserCohortMonth
  from question_stats qs
  left join user_activity ua on ua.UserId = qs.QuestionOwnerId
),
answerer_mix as (
  select q.QuestionId,
         count(distinct a.AnswerOwnerUserId) as DistinctAnswerers,
         sum(case when a.AnswerOwnerUserId = q.QuestionOwnerId then 1 else 0 end) as SelfAnswers
  from (
    select ap.QuestionId,
           ap.AnswerId,
           ap.AnswerOwnerId as AnswerOwnerUserId
    from a_posts ap
  ) a
  join q_posts q on q.QuestionId = a.QuestionId
  group by q.QuestionId, q.QuestionOwnerId
),
accepted_answer_stats as (
  select q.QuestionId,
         ap.AnswerId as AcceptedAnswerId,
         ap.AnswerScore as AcceptedAnswerScore,
         ap.AnswerCreated as AcceptedAnswerCreated
  from q_posts q
  left join a_posts ap on ap.AnswerId = q.AcceptedAnswerId
),
time_to_accept as (
  select q.QuestionId,
         case
           when a.AcceptedAnswerCreated is null then null
           else cast(extract(epoch from (a.AcceptedAnswerCreated - q.QuestionCreated)) as bigint)
         end as SecondsToAccept
  from q_posts q
  left join accepted_answer_stats a on a.QuestionId = q.QuestionId
),
ranked_questions as (
  select
    qs.QuestionId,
    qs.QuestionScore,
    qs.ViewCount,
    coalesce(va.UpVotes, 0) as UV,
    coalesce(va.DownVotes, 0) as DV,
    coalesce(ca.CommentCount, 0) as CC,
    dense_rank() over (order by qs.ViewCount desc) as r_views,
    dense_rank() over (order by qs.QuestionScore desc) as r_score,
    dense_rank() over (order by coalesce(va.UpVotes,0) - coalesce(va.DownVotes,0) desc) as r_netvotes,
    dense_rank() over (order by coalesce(ca.CommentCount,0) desc) as r_comments
  from question_stats qs
  left join vote_aggs va on va.PostId = qs.QuestionId
  left join comment_aggs ca on ca.PostId = qs.QuestionId
),
multi_metrics as (
  select
    rq.QuestionId,
    (rq.r_views + rq.r_score + rq.r_netvotes + rq.r_comments) as CompositeRank,
    (rq.UV - rq.DV) as NetVotes,
    case when rq.ViewCount > 0 then (cast(rq.UV as numeric) / rq.ViewCount) else null end as UV_per_view,
    case when rq.ViewCount > 0 then (cast(rq.CC as numeric) / rq.ViewCount) else null end as Comments_per_view
  from ranked_questions rq
),
recent_activity as (
  select p.Id as PostId,
         p.LastActivityDate,
         row_number() over (order by p.LastActivityDate desc) as RecentActivityRank
  from Posts p
  where p.PostTypeId = 1
),
null_edgecases as (
  select
    qs.QuestionId,
    case when qs.Tags is null then 1 else 0 end as IsNullTags,
    case when ph.FirstCloseDate is null and ph.CloseEvents > 0 then 1 else 0 end as AnomalousCloseState,
    case when va.Favorites is null then 1 else 0 end as MissingFavoritesCount
  from question_stats qs
  left join ph_close ph on ph.PostId = qs.QuestionId
  left join vote_aggs va on va.PostId = qs.QuestionId
  group by qs.QuestionId, ph.FirstCloseDate, ph.CloseEvents, va.Favorites, qs.Tags
),
latest_comment as (
  select c1.PostId,
         c1.Id as LatestCommentId,
         c1.CreationDate as LatestCommentDate,
         c1.Score as LatestCommentScore,
         left(coalesce(c1.Text, ''), 120) as LatestCommentSnippet
  from Comments c1
  where c1.Id = (
    select c2.Id
    from Comments c2
    where c2.PostId = c1.PostId
    order by c2.CreationDate desc, c2.Id desc
    limit 1
  )
),
mixed_cohort as (
  select qs.QuestionId from question_stats qs where qs.QuestionScore >= 5
  union
  select am.QuestionId from answerer_mix am where am.DistinctAnswerers >= 3
  except
  select pc.PostId from ph_close pc where pc.CloseEvents >= 1
),
final as (
  select
    qs.QuestionId,
    coalesce(om.UserId, -1) as OwnerUserId,
    coalesce(ua.DisplayName, '(unknown)') as OwnerDisplayName,
    om.Reputation,
    om.TotalBadges,
    om.GoldBadges,
    om.SilverBadges,
    om.BronzeBadges,
    om.LocationNorm,
    om.UserCohortMonth,
    qs.QuestionCreated,
    qs.Title,
    ft.FirstThreeTags,
    qs.Tags,
    qs.AnswersCount,
    am.DistinctAnswerers,
    am.SelfAnswers,
    aas.AcceptedAnswerId,
    tt.SecondsToAccept,
    qs.QuestionScore,
    qs.ViewCount,
    va.UpVotes,
    va.DownVotes,
    va.Favorites,
    va.BountyStarts,
    va.BountyTotal,
    ca.CommentCount,
    ca.CommentScoreSum,
    ca.CommentScoreAvg,
    ca.MaxCommentLen,
    ca.AnonymousComments,
    ph.FirstCloseDate,
    ph.LastReopenDate,
    ph.CloseEvents,
    ph.ReopenEvents,
    ph.ProtectEvents,
    dl.DuplicateLinks,
    dl.LinkedLinks,
    lm.LatestCommentId,
    lm.LatestCommentDate,
    lm.LatestCommentScore,
    lm.LatestCommentSnippet,
    ra.LastActivityDate,
    ra.RecentActivityRank,
    mm.CompositeRank,
    mm.NetVotes,
    mm.UV_per_view,
    mm.Comments_per_view,
    ne.IsNullTags,
    ne.AnomalousCloseState,
    ne.MissingFavoritesCount,
    case
      when qs.AnswersCount = 0 then 'Unanswered'
      when aas.AcceptedAnswerId is not null then 'Accepted'
      when qs.AnswersCount > 0 then 'Answered'
      else 'Unknown'
    end as AnswerState,
    case
      when qs.ViewCount is null then null
      when qs.ViewCount = 0 then 0
      else round((cast(qs.QuestionScore as numeric) / nullif(qs.ViewCount,0)) , 6)
    end as ScorePerView,
    case
      when om.Reputation >= 100000 then 'Legend'
      when om.Reputation >= 20000 then 'Veteran'
      when om.Reputation >= 3000 then 'Experienced'
      when om.Reputation is null then 'Anon'
      else 'Rookie'
    end as OwnerTier,
    case
      when lower(coalesce(qs.Tags,'')) like '%<sql>%' then 1
      when lower(coalesce(ft.FirstThreeTags,'')) like '%sql%' then 1
      else 0
    end as IsSQLTagged,
    length(coalesce(qs.Title, '')) as TitleLen,
    regexp_replace(coalesce(qs.Title, ''), '\s+', ' ', 'g') as TitleCompacted,
    upper(left(coalesce(qs.Title, ''), 1)) || lower(substring(coalesce(qs.Title, '') from 2)) as TitleCapitalized,
    (
      select count(1)
      from PostLinks pl
      where pl.RelatedPostId = qs.QuestionId
    ) as BacklinkCount,
    (
      select count(1)
      from Votes v
      where v.PostId = qs.QuestionId and v.VoteTypeId in (10,11,12)
    ) as ModActionVotes
  from question_stats qs
  left join owner_metrics om on om.QuestionId = qs.QuestionId
  left join Users ua on ua.Id = om.UserId
  left join vote_aggs va on va.PostId = qs.QuestionId
  left join comment_aggs ca on ca.PostId = qs.QuestionId
  left join ph_close ph on ph.PostId = qs.QuestionId
  left join dup_links dl on dl.DuplicateOfId = qs.QuestionId
  left join first_three_tags ft on ft.QuestionId = qs.QuestionId
  left join answerer_mix am on am.QuestionId = qs.QuestionId
  left join accepted_answer_stats aas on aas.QuestionId = qs.QuestionId
  left join time_to_accept tt on tt.QuestionId = qs.QuestionId
  left join latest_comment lm on lm.PostId = qs.QuestionId
  left join recent_activity ra on ra.PostId = qs.QuestionId
  left join multi_metrics mm on mm.QuestionId = qs.QuestionId
  left join null_edgecases ne on ne.QuestionId = qs.QuestionId
  where (
    (qs.QuestionScore >= 0 and coalesce(va.UpVotes,0) >= coalesce(va.DownVotes,0))
    and (ra.LastActivityDate is not null or coalesce(ca.CommentCount,0) > 0 or coalesce(va.Favorites,0) > 0)
    and (
      (qs.Tags is not null and (lower(qs.Tags) like '%<performance>%' or lower(qs.Tags) like '%<benchmark>%'))
      or (coalesce(mm.NetVotes,0) >= 10 and coalesce(qs.ViewCount,0) >= 100)
      or (tt.SecondsToAccept is not null and tt.SecondsToAccept <= 86400)
      or qs.AcceptedAnswerId is null
    )
    and not (coalesce(ph.CloseEvents,0) >= 1 and coalesce(ph.ReopenEvents,0) = 0)
  )
)
select
  f.*,
  ntile(10) over (order by coalesce(f.ViewCount,0) desc) as ViewCountDecile,
  row_number() over (partition by f.OwnerTier order by f.CompositeRank asc, f.ViewCount desc) as RowNumWithinOwnerTier,
  sum(coalesce(f.NetVotes,0)) over (partition by f.LocationNorm) as NetVotesByLocation,
  avg(f.ScorePerView) over (order by f.RecentActivityRank rows between unbounded preceding and current row) as RunningAvgScorePerView,
  lag(f.SecondsToAccept) over (order by f.QuestionCreated) as PrevSecondsToAccept,
  lead(f.SecondsToAccept) over (order by f.QuestionCreated) as NextSecondsToAccept
from final f
where f.QuestionCreated >= (select min(u.CreationDate) from Users u)
   or f.OwnerTier in ('Legend','Veteran')
order by f.CompositeRank asc, f.ViewCount desc
limit 500;