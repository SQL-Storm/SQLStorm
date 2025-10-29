with
q as (
  select
    p.Id as QuestionId,
    p.CreationDate as QuestionCreated,
    p.Score as QuestionScore,
    p.ViewCount,
    p.OwnerUserId as AskerId,
    p.Tags,
    p.Title,
    p.ClosedDate,
    coalesce(p.AnswerCount, 0) as AnswerCount
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select
    ap.Id as AnswerId,
    ap.ParentId as QuestionId,
    ap.OwnerUserId as AnswererId,
    ap.Score as AnswerScore,
    ap.CreationDate as AnswerCreated,
    ap.LastActivityDate as AnswerLastActivity
  from Posts ap
  where ap.PostTypeId = 2
),
first_answer as (
  select
    QuestionId, AnswerId, AnswererId, AnswerScore, AnswerCreated
  from (
    select
      a.*,
      row_number() over (partition by QuestionId order by AnswerCreated) as rn
    from a
  ) t
  where rn = 1
),
votes_by_post as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
    min(case when v.VoteTypeId in (8,9) then v.CreationDate end) as FirstBountyDate
  from Votes v
  group by v.PostId
),
accepted as (
  select
    q.Id as QuestionId,
    q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1
    and q.AcceptedAnswerId is not null
),
dup_links as (
  select
    pl.PostId as DuplicateOf,
    pl.RelatedPostId as OriginalQuestionId
  from PostLinks pl
  where pl.LinkTypeId = 3
),
ph_closed as (
  select ph.PostId, ph.CreationDate as ClosedEventDate,
         case when nullif(ph.Comment,'') ~ '^[0-9]+$' then cast(nullif(ph.Comment,'') as integer) else null end as CloseReasonId,
         ph.PostHistoryTypeId
  from PostHistory ph
  where ph.PostHistoryTypeId in (10,11,12,13,35)
),
user_stats as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    coalesce(nullif(trim(u.Location),''),'(unknown)') as LocationNorm,
    u.UpVotes as UserUpVotes,
    u.DownVotes as UserDownVotes,
    u.Views as ProfileViews
  from Users u
),
badge_agg as (
  select
    b.UserId,
    sum(case when b.Class = 1 then 1 else 0 end) as GoldCount,
    sum(case when b.Class = 2 then 1 else 0 end) as SilverCount,
    sum(case when b.Class = 3 then 1 else 0 end) as BronzeCount,
    count(*) as TotalBadges,
    min(b.Date) as FirstBadgeDate,
    max(b.Date) as LastBadgeDate
  from Badges b
  group by b.UserId
),
tag_expanded as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q
),
tag_rank as (
  select
    t.tag,
    count(*) as tag_q_count,
    dense_rank() over (order by count(*) desc, t.tag) as tag_pop_rank
  from tag_expanded t
  group by t.tag
),
question_tag_sample as (
  select t.QuestionId, t.tag,
         tr.tag_pop_rank,
         row_number() over (partition by t.QuestionId order by tr.tag_pop_rank, t.tag) as rn
  from tag_expanded t
  join tag_rank tr on tr.tag = t.tag
),
agg_comments as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(c.Score) as CommentScoreSum,
    max(c.CreationDate) as LastCommentDate,
    string_agg(substr(c.Text, 1, 50), ' | ' order by c.Score desc, c.CreationDate desc) as CommentSnippets
  from Comments c
  group by c.PostId
),
q_enriched as (
  select
    q.QuestionId,
    q.QuestionCreated,
    q.QuestionScore,
    q.ViewCount,
    q.AskerId,
    q.Tags,
    q.Title,
    q.ClosedDate,
    q.AnswerCount,
    vb.UpVotes as QUpVotes,
    vb.DownVotes as QDownVotes,
    vb.Favorites as QFavorites,
    vb.BountyTotal as QBountyTotal,
    vb.FirstBountyDate as QFirstBountyDate,
    ac.AcceptedAnswerId,
    phc.ClosedEventDate,
    phc.CloseReasonId,
    dl.OriginalQuestionId,
    ac2.AcceptedAnswerId as OriginalAcceptedAnswerId
  from q
  left join votes_by_post vb on vb.PostId = q.QuestionId
  left join accepted ac on ac.QuestionId = q.QuestionId
  left join ph_closed phc on phc.PostId = q.QuestionId
  left join dup_links dl on dl.DuplicateOf = q.QuestionId
  left join accepted ac2 on ac2.QuestionId = dl.OriginalQuestionId
),
answer_metrics as (
  select
    a.QuestionId,
    count(*) as AnswerTotal,
    avg(cast(a.AnswerScore as numeric)) as AvgAnswerScore,
    max(a.AnswerScore) as MaxAnswerScore,
    min(a.AnswerScore) as MinAnswerScore,
    min(a.AnswerCreated) as FirstAnswerDate,
    max(a.AnswerCreated) as LastAnswerDate
  from a
  group by a.QuestionId
),
activity_window as (
  select
    p.Id as PostId,
    p.PostTypeId,
    p.CreationDate,
    p.LastActivityDate,
    p.Score,
    sum(coalesce(vb.UpVotes,0) - coalesce(vb.DownVotes,0)) over (partition by p.PostTypeId order by p.CreationDate rows between unbounded preceding and current row) as CumNetVotesByType,
    avg(p.Score) over (partition by p.PostTypeId order by p.CreationDate rows between 100 preceding and current row) as MovingAvgScoreByType
  from Posts p
  left join votes_by_post vb on vb.PostId = p.Id
),
user_enriched as (
  select
    us.UserId,
    us.Reputation,
    us.CreationDate,
    us.LastAccessDate,
    us.LocationNorm,
    coalesce(ba.GoldCount,0) as GoldCount,
    coalesce(ba.SilverCount,0) as SilverCount,
    coalesce(ba.BronzeCount,0) as BronzeCount,
    coalesce(ba.TotalBadges,0) as TotalBadges,
    ba.FirstBadgeDate,
    ba.LastBadgeDate
  from user_stats us
  left join badge_agg ba on ba.UserId = us.UserId
),
question_quality as (
  select
    qe.QuestionId,
    qe.Title,
    length(coalesce(qe.Title,'')) as TitleLen,
    length(coalesce(qe.Tags,'')) as TagsLen,
    case when qe.ViewCount is null or qe.ViewCount = 0 then null else cast(qe.QuestionScore as numeric) / qe.ViewCount end as ScorePerView,
    case when qe.AnswerCount = 0 then null else cast(qe.QuestionScore as numeric) / qe.AnswerCount end as ScorePerAnswer,
    case when qe.QUpVotes + qe.QDownVotes is null or qe.QUpVotes + qe.QDownVotes = 0 then null else cast(qe.QUpVotes as numeric) / nullif(qe.QUpVotes + qe.QDownVotes,0) end as UpvoteRatio,
    case when qe.ClosedDate is not null then 1 else 0 end as IsClosed
  from q_enriched qe
),
top_tags as (
  select qt.QuestionId,
         max(case when qt.rn = 1 then qt.tag end) as Tag1,
         max(case when qt.rn = 2 then qt.tag end) as Tag2,
         max(case when qt.rn = 3 then qt.tag end) as Tag3
  from question_tag_sample qt
  where qt.rn <= 3
  group by qt.QuestionId
),
assembled as (
  select
    qe.QuestionId,
    qe.Title,
    coalesce(tt.Tag1,'') as Tag1,
    coalesce(tt.Tag2,'') as Tag2,
    coalesce(tt.Tag3,'') as Tag3,
    qe.QuestionCreated,
    qe.QuestionScore,
    qe.ViewCount,
    qe.AnswerCount,
    qe.QUpVotes,
    qe.QDownVotes,
    qe.QFavorites,
    qe.QBountyTotal,
    qe.QFirstBountyDate,
    qe.AcceptedAnswerId,
    qe.ClosedEventDate,
    qe.CloseReasonId,
    qe.OriginalQuestionId,
    qe.OriginalAcceptedAnswerId,
    am.AnswerTotal,
    am.AvgAnswerScore,
    am.MaxAnswerScore,
    am.MinAnswerScore,
    am.FirstAnswerDate,
    am.LastAnswerDate,
    fq.AnswerId as FirstAnswerId,
    fq.AnswererId,
    fq.AnswerScore as FirstAnswerScore,
    fq.AnswerCreated as FirstAnswerCreated,
    aq.TitleLen,
    aq.TagsLen,
    aq.ScorePerView,
    aq.ScorePerAnswer,
    aq.UpvoteRatio,
    aq.IsClosed,
    ua.UserId as AskerId,
    ua.Reputation as AskerRep,
    ua.LocationNorm as AskerLocation,
    ua.TotalBadges as AskerBadgeCount,
    uf.UserId as FirstAnswererId,
    uf.Reputation as FirstAnswererRep,
    uf.LocationNorm as FirstAnswererLocation,
    uf.TotalBadges as FirstAnswererBadgeCount,
    acs.CommentCount as QCommentCount,
    acs.CommentScoreSum as QCommentScoreSum,
    acs.LastCommentDate as QLastCommentDate,
    acs.CommentSnippets as QCommentSnippets
  from q_enriched qe
  left join answer_metrics am on am.QuestionId = qe.QuestionId
  left join first_answer fq on fq.QuestionId = qe.QuestionId
  left join user_enriched ua on ua.UserId = qe.AskerId
  left join user_enriched uf on uf.UserId = fq.AnswererId
  left join agg_comments acs on acs.PostId = qe.QuestionId
  left join question_quality aq on aq.QuestionId = qe.QuestionId
  left join top_tags tt on tt.QuestionId = qe.QuestionId
),
ranked as (
  select
    a.QuestionId,
    a.Title,
    a.Tag1,
    a.Tag2,
    a.Tag3,
    a.QuestionCreated,
    a.QuestionScore,
    a.ViewCount,
    a.AnswerCount,
    a.QUpVotes,
    a.QDownVotes,
    a.QFavorites,
    a.QBountyTotal,
    a.QFirstBountyDate,
    a.AcceptedAnswerId,
    a.ClosedEventDate,
    a.CloseReasonId,
    a.OriginalQuestionId,
    a.OriginalAcceptedAnswerId,
    a.AnswerTotal,
    a.AvgAnswerScore,
    a.MaxAnswerScore,
    a.MinAnswerScore,
    a.FirstAnswerDate,
    a.LastAnswerDate,
    a.FirstAnswerId,
    a.AnswererId,
    a.FirstAnswerScore,
    a.FirstAnswerCreated,
    a.TitleLen,
    a.TagsLen,
    a.ScorePerView,
    a.ScorePerAnswer,
    a.UpvoteRatio,
    a.IsClosed,
    a.AskerId,
    a.AskerRep,
    a.AskerLocation,
    a.AskerBadgeCount,
    a.FirstAnswererId,
    a.FirstAnswererRep,
    a.FirstAnswererLocation,
    a.FirstAnswererBadgeCount,
    a.QCommentCount,
    a.QCommentScoreSum,
    a.QLastCommentDate,
    a.QCommentSnippets,
    row_number() over (order by coalesce(a.QBountyTotal,0) desc, coalesce(a.ViewCount,0) desc, coalesce(a.QuestionScore,0) desc) as GlobalRank,
    dense_rank() over (partition by coalesce(a.IsClosed,0) order by coalesce(a.QFavorites,0) desc) as RankWithinClosedFlag,
    percent_rank() over (order by coalesce(a.ScorePerView, -1)) as PR_ScorePerView,
    ntile(10) over (order by coalesce(a.ViewCount,0)) as ViewCountDecile,
    case
      when a.ClosedEventDate is not null and a.FirstAnswerDate is not null and a.FirstAnswerDate > a.ClosedEventDate then 1
      else 0
    end as FirstAnswerAfterCloseFlag,
    case
      when a.AcceptedAnswerId is not null and a.FirstAnswerId = a.AcceptedAnswerId then 1 else 0
    end as FirstAnswerAcceptedFlag
  from assembled a
),
high_view as (
  select QuestionId from ranked where ViewCount >= (select percentile_disc(0.90) within group (order by coalesce(ViewCount,0)) from ranked)
),
high_bounty as (
  select QuestionId from ranked where QBountyTotal > 0
),
candidate as (
  select QuestionId from high_view
  union
  select QuestionId from high_bounty
),
final_base as (
  select r.*
  from ranked r
  join candidate c on c.QuestionId = r.QuestionId
),
final as (
  select
    fb.*,
    aw.CumNetVotesByType,
    aw.MovingAvgScoreByType
  from final_base fb
  left join activity_window aw on aw.PostId = fb.QuestionId and aw.PostTypeId = 1
)
select *
from final
where
  (
    coalesce(position(lower(coalesce(Tag1,'')) in lower(coalesce(Title,''))), 0) > 0
    or coalesce(position(lower(coalesce(Tag2,'')) in lower(coalesce(Title,''))), 0) > 0
    or coalesce(position(lower(coalesce(Tag3,'')) in lower(coalesce(Title,''))), 0) > 0
  )
  and coalesce(AskerRep,0) + coalesce(FirstAnswererRep,0) >= 0
  and (QCommentCount is null or QCommentCount >= 0)
  and (FirstAnswerDate is null or FirstAnswerDate >= QuestionCreated)
  and (OriginalQuestionId is null or OriginalQuestionId <> QuestionId)
order by GlobalRank, QuestionId
limit 500;