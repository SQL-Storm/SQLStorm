-- {"query": "498.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3176}
with recent_users as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.Location,
           coalesce(nullif(trim(split_part(coalesce(u.WebsiteUrl, ''), '/', 3)), ''), 'unknown') as Domain,
           row_number() over (order by u.Reputation desc, u.Id) as rn_rep
    from Users u
    where u.CreationDate >= (select date_trunc('year', max(CreationDate)) - interval '3 years' from Users)
),
-- replace tag string splitting with a derived table that extracts tags using recursive-like approach compatible with many dialects
post_tags as (
    select p.OwnerUserId as UserId,
           trim(tag) as TagName
    from Posts p
    cross join lateral (
        select regexp_split_to_table(
            case when p.Tags is null then '' else substring(p.Tags from 2 for greatest(char_length(p.Tags)-2,0)) end,
            '\>\<'
        ) as tag
    ) t
    where p.PostTypeId = 1
      and p.Tags is not null
      and p.OwnerUserId is not null
),
top_tags as (
    select pt.UserId,
           pt.TagName,
           count(*) as TagUses,
           sum(p.Score) as TagScore,
           avg(p.Score) as AvgTagScore
    from post_tags pt
    join Posts p on p.OwnerUserId = pt.UserId
        and p.PostTypeId = 1
        and p.Tags is not null
        and p.OwnerUserId is not null
    group by pt.UserId, pt.TagName
),
tag_rank as (
    select t.*,
           dense_rank() over (partition by t.UserId order by t.TagUses desc, t.TagScore desc, t.TagName) as tag_rank
    from top_tags t
),
user_top3_tags as (
    select UserId,
           array_agg(TagName order by tag_rank) filter (where tag_rank <= 3) as Top3Tags,
           sum(TagUses) filter (where tag_rank <= 3) as Top3TagUses,
           sum(TagScore) filter (where tag_rank <= 3) as Top3TagScore
    from tag_rank
    group by UserId
),
post_activity as (
    select p.OwnerUserId as UserId,
           count(*) filter (where p.PostTypeId = 1) as Questions,
           count(*) filter (where p.PostTypeId = 2) as Answers,
           sum(coalesce(p.Score,0)) as TotalScore,
           avg(nullif(p.Score,0)) as AvgNonZeroScore,
           max(p.ViewCount) as MaxViews,
           count(*) filter (where p.ClosedDate is not null) as ClosedCount,
           count(distinct case when p.PostTypeId=1 then p.Id end) as DistinctQuestions,
           count(distinct case when p.PostTypeId=2 then p.ParentId end) as DistinctAnsweredQuestions
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
vote_summaries as (
    select v.PostId,
           sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
           sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
           sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
           sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
           count(*) as TotalVotes
    from Votes v
    group by v.PostId
),
user_vote_agg as (
    select p.OwnerUserId as UserId,
           sum(coalesce(vs.UpVotes,0)) as ReceivedUpVotes,
           sum(coalesce(vs.DownVotes,0)) as ReceivedDownVotes,
           sum(coalesce(vs.Favorites,0)) as ReceivedFavorites,
           sum(coalesce(vs.BountyTotal,0)) as ReceivedBounty,
           sum(coalesce(vs.TotalVotes,0)) as ReceivedVotes
    from Posts p
    left join vote_summaries vs on vs.PostId = p.Id
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
comment_stats as (
    select c.UserId as UserId,
           count(*) as CommentsMade,
           avg(char_length(c.Text)) as AvgCommentLen,
           sum(case when c.Score > 0 then 1 else 0 end) as PosComments,
           sum(case when c.Score < 0 then 1 else 0 end) as NegComments
    from Comments c
    where c.UserId is not null
    group by c.UserId
),
badge_pivot as (
    select b.UserId,
           sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
           sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
           sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
           sum(case when b.TagBased = true then 1 else 0 end) as TagBadges,
           count(*) as TotalBadges,
           min(b.Date) as FirstBadgeDate,
           max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
question_closure as (
    select ph.PostId,
           min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosedDate,
           max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as LastReopenedDate,
           count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount,
           count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenVotesCount,
           count(*) filter (where ph.PostHistoryTypeId = 10 and ph.Comment in ('101','102','103','104','105','1','2','3','4','7','10','20')) as CloseWithReason
    from PostHistory ph
    group by ph.PostId
),
dup_links as (
    select pl.PostId,
           count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
           count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
           count(distinct case when pl.LinkTypeId = 3 then pl.RelatedPostId end) as DistinctDupTargets
    from PostLinks pl
    group by pl.PostId
),
question_metrics as (
    select q.OwnerUserId as UserId,
           count(*) as QuestionsTotal,
           sum(case when qc.FirstClosedDate is not null then 1 else 0 end) as ClosedQuestions,
           sum(coalesce(dl.DuplicateLinks,0)) as DuplicateLinksOnQuestions,
           sum(case when q.AcceptedAnswerId is not null then 1 else 0 end) as AcceptedAnswerQuestions,
           avg(q.ViewCount) as AvgQuestionViews
    from Posts q
    left join question_closure qc on qc.PostId = q.Id
    left join dup_links dl on dl.PostId = q.Id
    where q.PostTypeId = 1 and q.OwnerUserId is not null
    group by q.OwnerUserId
),
answer_metrics as (
    select a.OwnerUserId as UserId,
           count(*) as AnswersTotal,
           sum(case when exists (
                 select 1
                 from Posts q
                 where q.Id = a.ParentId
                   and q.AcceptedAnswerId = a.Id
           ) then 1 else 0 end) as AcceptedAnswersWon,
           avg(a.Score) as AvgAnswerScore
    from Posts a
    where a.PostTypeId = 2 and a.OwnerUserId is not null
    group by a.OwnerUserId
),
user_activity_window as (
    select p.OwnerUserId as UserId,
           p.Id as PostId,
           p.PostTypeId,
           p.CreationDate,
           sum(1) over (partition by p.OwnerUserId order by p.CreationDate rows between unbounded preceding and current row) as CumPosts,
           count(*) filter (where p.PostTypeId = 1) over (partition by p.OwnerUserId) as TotalQ,
           count(*) filter (where p.PostTypeId = 2) over (partition by p.OwnerUserId) as TotalA,
           lag(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate) as PrevPostDate,
           extract(epoch from (p.CreationDate - lag(p.CreationDate) over (partition by p.OwnerUserId order by p.CreationDate))) as SecondsSincePrev
    from Posts p
    where p.OwnerUserId is not null
),
user_first_last as (
    select UserId,
           min(CreationDate) as FirstPostDate,
           max(CreationDate) as LastPostDate,
           avg(SecondsSincePrev) as AvgInterPostSeconds
    from user_activity_window
    group by UserId
),
domain_stats as (
    select Domain,
           count(*) as UsersWithDomain,
           avg(Reputation) as AvgRepByDomain
    from recent_users
    group by Domain
),
rep_percentiles as (
    select u.Id as UserId,
           percent_rank() over (order by u.Reputation) as RepPct,
           cume_dist() over (order by u.Reputation) as RepCume
    from Users u
),
power_users as (
    select u.Id as UserId
    from Users u
    where u.Reputation >= (
        select percentile_disc(0.95) within group (order by Reputation) from Users
    )
),
final_scores as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           coalesce(pa.Questions,0) as Questions,
           coalesce(pa.Answers,0) as Answers,
           coalesce(qm.QuestionsTotal,0) as QuestionsTotal,
           coalesce(am.AnswersTotal,0) as AnswersTotal,
           coalesce(am.AcceptedAnswersWon,0) as AcceptedAnswersWon,
           coalesce(qm.AcceptedAnswerQuestions,0) as AcceptedAnswerQuestions,
           coalesce(uv.ReceivedUpVotes,0) as UpVotesRecv,
           coalesce(uv.ReceivedDownVotes,0) as DownVotesRecv,
           coalesce(b.TotalBadges,0) as TotalBadges,
           coalesce(b.GoldBadges,0) as GoldBadges,
           coalesce(cs.CommentsMade,0) as CommentsMade,
           coalesce(qm.ClosedQuestions,0) as ClosedQuestions,
           coalesce(qm.DuplicateLinksOnQuestions,0) as DuplicateLinksOnQuestions,
           coalesce(ut.Top3TagScore,0) as Top3TagScore,
           coalesce(ut.Top3TagUses,0) as Top3TagUses,
           coalesce(uv.ReceivedBounty,0) as BountyReceived,
           coalesce(pa.TotalScore,0) as TotalPostScore,
           coalesce(pa.AvgNonZeroScore,0.0) as AvgNonZeroScore,
           coalesce(pa.MaxViews,0) as MaxViews,
           coalesce(afl.AvgInterPostSeconds,0.0) as AvgInterPostSeconds,
           case when pu.UserId is not null then 1 else 0 end as IsPowerUser
    from Users u
    left join post_activity pa on pa.UserId = u.Id
    left join question_metrics qm on qm.UserId = u.Id
    left join answer_metrics am on am.UserId = u.Id
    left join user_vote_agg uv on uv.UserId = u.Id
    left join comment_stats cs on cs.UserId = u.Id
    left join badge_pivot b on b.UserId = u.Id
    left join user_top3_tags ut on ut.UserId = u.Id
    left join user_first_last afl on afl.UserId = u.Id
    left join power_users pu on pu.UserId = u.Id
),
ranked as (
    select f.UserId,
           f.DisplayName,
           f.Reputation,
           f.Questions,
           f.Answers,
           f.QuestionsTotal,
           f.AnswersTotal,
           f.AcceptedAnswersWon,
           f.AcceptedAnswerQuestions,
           f.UpVotesRecv,
           f.DownVotesRecv,
           f.TotalBadges,
           f.GoldBadges,
           f.CommentsMade,
           f.ClosedQuestions,
           f.DuplicateLinksOnQuestions,
           f.Top3TagScore,
           f.Top3TagUses,
           f.BountyReceived,
           f.TotalPostScore,
           f.AvgNonZeroScore,
           f.MaxViews,
           f.AvgInterPostSeconds,
           f.IsPowerUser,
           f.DisplayName as f_DisplayName_for_grouping,
           rep.RepPct,
           rep.RepCume,
           row_number() over (
               order by
                 (coalesce(f.AnswersTotal,0)*2 + coalesce(f.AcceptedAnswersWon,0)*3 + coalesce(f.QuestionsTotal,0)) desc,
                 coalesce(f.TotalPostScore,0) desc,
                 coalesce(f.UpVotesRecv,0) desc,
                 f.Reputation desc,
                 f.UserId
           ) as ActivityRank
    from final_scores f
    left join rep_percentiles rep on rep.UserId = f.UserId
),
domain_join as (
    select r.UserId,
           r.DisplayName,
           r.Reputation,
           r.Questions,
           r.Answers,
           r.QuestionsTotal,
           r.AnswersTotal,
           r.AcceptedAnswersWon,
           r.AcceptedAnswerQuestions,
           r.UpVotesRecv,
           r.DownVotesRecv,
           r.TotalBadges,
           r.GoldBadges,
           r.CommentsMade,
           r.ClosedQuestions,
           r.DuplicateLinksOnQuestions,
           r.Top3TagScore,
           r.Top3TagUses,
           r.BountyReceived,
           r.TotalPostScore,
           r.AvgNonZeroScore,
           r.MaxViews,
           r.AvgInterPostSeconds,
           r.IsPowerUser,
           r.RepPct,
           r.RepCume,
           r.ActivityRank,
           ru.Domain,
           ds.UsersWithDomain,
           ds.AvgRepByDomain
    from ranked r
    left join recent_users ru on ru.UserId = r.UserId
    left join domain_stats ds on ds.Domain = ru.Domain
)
select
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.ActivityRank,
    r.RepPct,
    r.RepCume,
    r.QuestionsTotal,
    r.AnswersTotal,
    r.AcceptedAnswersWon,
    r.AcceptedAnswerQuestions,
    r.UpVotesRecv,
    r.DownVotesRecv,
    r.TotalBadges,
    r.GoldBadges,
    r.CommentsMade,
    r.ClosedQuestions,
    r.DuplicateLinksOnQuestions,
    r.Top3TagScore,
    r.Top3TagUses,
    r.BountyReceived,
    r.TotalPostScore,
    r.AvgNonZeroScore,
    r.MaxViews,
    r.AvgInterPostSeconds,
    r.IsPowerUser,
    dj.Domain,
    dj.UsersWithDomain,
    dj.AvgRepByDomain,
    coalesce(array_to_string((select t.Top3Tags from user_top3_tags t where t.UserId = r.UserId), ', '), '(none)') as Top3Tags,
    coalesce(round(100.0 * nullif(r.AcceptedAnswersWon,0) / nullif(r.AnswersTotal,0), 2), 0.0) as AcceptedAnswerWinRatePct,
    case
      when r.QuestionsTotal = 0 and r.AnswersTotal = 0 then 'inactive'
      when r.AnswersTotal >= r.QuestionsTotal then 'answerer'
      else 'asker'
    end as Role,
    case
      when r.Reputation >= 100000 then 'legendary'
      when r.Reputation >= 50000 then 'elite'
      when r.Reputation >= 10000 then 'advanced'
      when r.Reputation >= 1000 then 'intermediate'
      else 'novice'
    end as ReputationTier
from domain_join r
left join domain_join dj on dj.UserId = r.UserId
where coalesce(r.AnswersTotal,0) + coalesce(r.QuestionsTotal,0) > 0
  and (coalesce(r.UpVotesRecv,0) - coalesce(r.DownVotesRecv,0)) >= 0
  and (r.ClosedQuestions is null or r.ClosedQuestions <= coalesce(r.QuestionsTotal,0))
order by r.ActivityRank
limit 500;