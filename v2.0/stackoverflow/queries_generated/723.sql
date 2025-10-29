-- {"query": "723.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2998} 
with
q_posts as (
  select p.Id as QuestionId,
         p.CreationDate as QCreated,
         p.Score as QScore,
         p.ViewCount as QViews,
         p.OwnerUserId as QOwnerId,
         p.AcceptedAnswerId,
         p.Tags,
         p.Title
  from Posts p
  where p.PostTypeId = 1
),
a_posts as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AOwnerId,
         a.Score as AScore,
         a.CreationDate as ACreated
  from Posts a
  where a.PostTypeId = 2
),
q_with_answers as (
  select q.*,
         count(a.AnswerId) as AnswerCnt,
         max(a.AScore) as MaxAnswerScore,
         sum(case when a.AnswerId = q.AcceptedAnswerId then 1 else 0 end) as HasAccepted
  from q_posts q
  left join a_posts a on a.QuestionId = q.QuestionId
  group by q.QuestionId, q.QCreated, q.QScore, q.QViews, q.QOwnerId, q.AcceptedAnswerId, q.Tags, q.Title
),
user_stats as (
  select u.Id as UserId,
         u.Reputation,
         u.UpVotes,
         u.DownVotes,
         u.Views as ProfileViews,
         u.CreationDate as UserCreated,
         coalesce(nullif(trim(u.Location), ''), 'Unknown') as NormLocation
  from Users u
),
badge_rollup as (
  select b.UserId,
         sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
         sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
         sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
         count(*) as TotalBadges,
         max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
comment_activity as (
  select c.PostId,
         count(*) as CommentCount,
         avg(c.Score) as AvgCommentScore,
         max(c.CreationDate) as LastCommentAt,
         sum(case when c.Text ilike '%thanks%' or c.Text ilike '%thank you%' then 1 else 0 end) as ThankfulComments
  from Comments c
  group by c.PostId
),
vote_rollup as (
  select v.PostId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
         sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyFlow
  from Votes v
  group by v.PostId
),
q_edit_events as (
  select ph.PostId,
         count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditAt,
         max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditAt,
         count(*) filter (where ph.PostHistoryTypeId in (10)) as CloseVotesEvents,
         count(*) filter (where ph.PostHistoryTypeId in (11)) as ReopenEvents,
         count(*) filter (where ph.PostHistoryTypeId in (19)) as ProtectEvents
  from PostHistory ph
  group by ph.PostId
),
dup_links as (
  select pl.PostId as DupOfQuestionId,
         count(*) as DuplicateMarks,
         max(pl.CreationDate) as LastDupMark
  from PostLinks pl
  where pl.LinkTypeId = 3
  group by pl.PostId
),
tag_expansion as (
  select q.QuestionId,
         unnest(string_to_array(substring(coalesce(q.Tags,''), 2, greatest(length(coalesce(q.Tags,'')) - 2, 0)), '><')) as tag
  from q_posts q
),
tag_top as (
  select te.QuestionId,
         te.tag,
         t.Count as TagGlobalCount,
         row_number() over (partition by te.QuestionId order by coalesce(t.Count,0) desc, te.tag) as rn
  from tag_expansion te
  left join Tags t on lower(t.TagName) = lower(te.tag)
),
question_top_tag as (
  select QuestionId,
         max(tag) filter (where rn = 1) as TopTag,
         max(TagGlobalCount) filter (where rn = 1) as TopTagGlobalCount
  from tag_top
  group by QuestionId
),
answer_rank as (
  select a.*,
         rank() over (partition by a.QuestionId order by a.AScore desc nulls last, a.ACreated asc) as ScoreRank,
         dense_rank() over (partition by a.QuestionId order by a.ACreated asc) as FirstAnswerRank,
         min(a.ACreated) over (partition by a.QuestionId) as FirstAnswerTime
  from a_posts a
),
accepted_vs_best as (
  select q.QuestionId,
         case when q.AcceptedAnswerId is not null then 1 else 0 end as HasAccepted,
         case when exists (
           select 1
           from answer_rank ar
           where ar.QuestionId = q.QuestionId
             and ar.AnswerId = q.AcceptedAnswerId
             and ar.ScoreRank = 1
         ) then 1 else 0 end as AcceptedIsTopByScore
  from q_posts q
),
question_quality as (
  select q.QuestionId,
         q.QScore,
         q.QViews,
         qr.UpVotes as QUp,
         qr.DownVotes as QDown,
         qr.Favorites as QFav,
         greatest(1, q.QViews) as SafeViews,
         (coalesce(qr.UpVotes,0) - coalesce(qr.DownVotes,0)) as NetVotes,
         (coalesce(qr.UpVotes,0) + coalesce(qr.DownVotes,0)) as TotalVotes
  from q_posts q
  left join vote_rollup qr on qr.PostId = q.QuestionId
),
normalized_quality as (
  select qq.QuestionId,
         qq.QScore,
         qq.QViews,
         qq.QUp,
         qq.QDown,
         qq.QFav,
         qq.NetVotes,
         qq.TotalVotes,
         round((qq.NetVotes::numeric / qq.SafeViews) * 1000, 3) as NetVotesPerKView,
         round((qq.TotalVotes::numeric / qq.SafeViews) * 1000, 3) as VotesPerKView,
         round((qq.QFav::numeric / qq.SafeViews) * 1000, 3) as FavPerKView
  from question_quality qq
),
owner_enriched as (
  select q.QuestionId,
         qs.Title,
         qs.Tags,
         qs.AnswerCnt,
         qs.MaxAnswerScore,
         qs.HasAccepted,
         u.UserId as OwnerId,
         coalesce(u.Reputation, 1) as OwnerRep,
         coalesce(b.TotalBadges,0) as OwnerBadges,
         coalesce(b.GoldCount,0) as OwnerGold,
         coalesce(b.SilverCount,0) as OwnerSilver,
         coalesce(b.BronzeCount,0) as OwnerBronze,
         u.NormLocation as OwnerLocation,
         u.ProfileViews as OwnerProfileViews,
         u.UserCreated as OwnerCreated
  from q_with_answers qs
  left join user_stats u on u.UserId = qs.QOwnerId
  left join badge_rollup b on b.UserId = qs.QOwnerId
),
question_health as (
  select oe.QuestionId,
         oe.Title,
         oe.Tags,
         oe.AnswerCnt,
         oe.MaxAnswerScore,
         oe.HasAccepted,
         oe.OwnerId,
         oe.OwnerRep,
         oe.OwnerBadges,
         oe.OwnerGold,
         oe.OwnerSilver,
         oe.OwnerBronze,
         oe.OwnerLocation,
         oe.OwnerProfileViews,
         oe.OwnerCreated,
         nq.QScore,
         nq.QViews,
         nq.QUp,
         nq.QDown,
         nq.QFav,
         nq.NetVotes,
         nq.TotalVotes,
         nq.NetVotesPerKView,
         nq.VotesPerKView,
         nq.FavPerKView,
         coalesce(ce.CommentCount,0) as CommentCount,
         coalesce(ce.AvgCommentScore,0) as AvgCommentScore,
         ce.LastCommentAt,
         coalesce(ce.ThankfulComments,0) as ThankfulComments,
         coalesce(qe.EditCount,0) as EditCount,
         qe.FirstEditAt,
         qe.LastEditAt,
         coalesce(qe.CloseVotesEvents,0) as CloseVotesEvents,
         coalesce(qe.ReopenEvents,0) as ReopenEvents,
         coalesce(qe.ProtectEvents,0) as ProtectEvents,
         coalesce(dl.DuplicateMarks,0) as DuplicateMarks,
         dl.LastDupMark
  from owner_enriched oe
  left join normalized_quality nq on nq.QuestionId = oe.QuestionId
  left join comment_activity ce on ce.PostId = oe.QuestionId
  left join q_edit_events qe on qe.PostId = oe.QuestionId
  left join dup_links dl on dl.DupOfQuestionId = oe.QuestionId
),
accepted_answer_latency as (
  select q.QuestionId,
         min(a.ACreated) filter (where a.AnswerId = q.AcceptedAnswerId) as AcceptedAt,
         min(a.ACreated) as FirstAnswerAt
  from q_posts q
  left join a_posts a on a.QuestionId = q.QuestionId
  group by q.QuestionId
),
final_scored as (
  select
    qh.*,
    qat.AcceptedAt,
    qat.FirstAnswerAt,
    qt.TopTag,
    qt.TopTagGlobalCount,
    avb.AcceptedIsTopByScore,
    -- composite score mixing engagement, quality, and hygiene
    round((
      coalesce(qh.NetVotesPerKView,0) * 0.35 +
      coalesce(qh.FavPerKView,0) * 0.25 +
      least(5, coalesce(qh.AvgCommentScore,0)) * 0.1 +
      case when qh.HasAccepted = 1 then 1.0 else 0.0 end * 2.0 +
      case when coalesce(qh.DuplicateMarks,0) > 0 then -2.5 else 0 end +
      greatest(-3, least(3, coalesce(qh.EditCount,0) * 0.15)) +
      least(3, ln(greatest(1, qh.OwnerRep))) * 0.4
    )::numeric, 3) as CompositeScore
  from question_health qh
  left join accepted_answer_latency qat on qat.QuestionId = qh.QuestionId
  left join question_top_tag qt on qt.QuestionId = qh.QuestionId
  left join accepted_vs_best avb on avb.QuestionId = qh.QuestionId
),
ranked as (
  select
    fs.*,
    row_number() over (order by fs.CompositeScore desc nulls last, fs.QViews desc nulls last) as RN_Global,
    rank() over (partition by coalesce(fs.TopTag, 'untagged') order by fs.CompositeScore desc nulls last) as RN_ByTopTag,
    ntile(10) over (order by fs.CompositeScore desc nulls last) as Decile
  from final_scored fs
),
filtered as (
  select r.*
  from ranked r
  where
    -- non-trivial predicates combining null logic and string ops
    (r.QViews is not null and r.QViews > 50)
    and (
      r.Title ilike any (array['%how to%','%best way%','%performance%','%optimiz%'])
      or (coalesce(r.Tags,'') <> '' and position('performance' in lower(r.Tags)) > 0)
    )
    and (
      r.DuplicateMarks = 0
      or (r.DuplicateMarks > 0 and r.ReopenEvents > 0)
    )
    and (
      r.OwnerLocation is null
      or r.OwnerLocation not ilike any (array['%stackoverflow%','%internet%'])
      or length(r.OwnerLocation) >= 3
    )
)
select
  f.QuestionId,
  coalesce(f.Title, '(no title)') as Title,
  coalesce(f.TopTag, 'untagged') as TopTag,
  f.TopTagGlobalCount,
  f.CompositeScore,
  f.Decile,
  f.RN_Global,
  f.RN_ByTopTag,
  f.QScore,
  f.QViews,
  f.QUp,
  f.QDown,
  f.QFav,
  f.NetVotes,
  f.TotalVotes,
  f.NetVotesPerKView,
  f.VotesPerKView,
  f.FavPerKView,
  f.AnswerCnt,
  f.MaxAnswerScore,
  f.HasAccepted,
  f.AcceptedIsTopByScore,
  f.AcceptedAt,
  f.FirstAnswerAt,
  f.EditCount,
  f.CloseVotesEvents,
  f.ReopenEvents,
  f.ProtectEvents,
  f.DuplicateMarks,
  f.OwnerId,
  f.OwnerRep,
  f.OwnerBadges,
  f.OwnerGold,
  f.OwnerSilver,
  f.OwnerBronze,
  coalesce(nullif(trim(f.OwnerLocation), ''), 'Unknown') as OwnerLocation,
  f.OwnerProfileViews
from filtered f
order by f.CompositeScore desc nulls last, f.QViews desc nulls last
limit 250;