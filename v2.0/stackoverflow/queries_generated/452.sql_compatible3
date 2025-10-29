with recent_questions as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        row_number() over (order by p.CreationDate desc, p.Id desc) as rn
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (
          select date_trunc('month', max(CreationDate)) - interval '6 months'
          from Posts where PostTypeId = 1
      )
),
top_recent as (
    select *
    from recent_questions
    where rn <= 5000
),
answers as (
    select
        a.ParentId as QuestionId,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc, a.Id asc) as rn_best_by_score,
        max(a.Score) over (partition by a.ParentId) as max_answer_score,
        count(*) over (partition by a.ParentId) as AnswerCntWin
    from Posts a
    where a.PostTypeId = 2
),
accepted_answers as (
    select q.Id as QuestionId, q.AcceptedAnswerId
    from Posts q
    where q.PostTypeId = 1
      and q.AcceptedAnswerId is not null
),
user_enrichment as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        coalesce(u.UpVotes,0) - coalesce(u.DownVotes,0) as NetVotes,
        coalesce(nullif(bc.BronzeCnt,0),0) as BronzeCnt,
        coalesce(nullif(bc.SilverCnt,0),0) as SilverCnt,
        coalesce(nullif(bc.GoldCnt,0),0) as GoldCnt,
        (coalesce(bc.GoldCnt,0)*3 + coalesce(bc.SilverCnt,0)*2 + coalesce(bc.BronzeCnt,0)) as BadgeScore
    from Users u
    left join (
        select
            b.UserId,
            sum(case when b.Class = 3 then 1 else 0 end) as BronzeCnt,
            sum(case when b.Class = 2 then 1 else 0 end) as SilverCnt,
            sum(case when b.Class = 1 then 1 else 0 end) as GoldCnt,
            min(b.Date) as FirstBadgeDate,
            max(b.Date) as LastBadgeDate
        from Badges b
        group by b.UserId
    ) bc on bc.UserId = u.Id
),
tag_explode as (
    select
        tr.QuestionId,
        unnest(string_to_array(substring(tr.Tags, 2, length(tr.Tags)-2), '><')) as tag
    from top_recent tr
    where tr.Tags is not null
      and length(tr.Tags) > 2
),
tag_stats as (
    select
        te.QuestionId,
        count(*) as TagCount,
        string_agg(te.tag, ',' order by te.tag) as TagListCsv,
        max(case when lower(te.tag) like '%sql%' then te.tag else null end) as HasSQLTag
    from tag_explode te
    group by te.QuestionId
),
vote_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpvoteCnt,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownvoteCnt,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteCnt,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStartAmt,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyCloseAmt,
        count(*) as TotalVotes
    from Votes v
    group by v.PostId
),
comment_agg as (
    select
        c.PostId,
        count(*) as CommentCnt,
        max(c.CreationDate) as LastCommentDate,
        sum(case when c.Score > 0 then 1 else 0 end) as PosCommentCnt,
        sum(case when c.Score < 0 then 1 else 0 end) as NegCommentCnt,
        max(length(coalesce(c.Text,''))) as MaxCommentLen
    from Comments c
    group by c.PostId
),
link_agg as (
    select
        pl.PostId,
        sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedCnt,
        sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateCnt,
        count(*) as TotalLinks,
        bool_or(pl.LinkTypeId = 3) as HasDuplicateMark
    from PostLinks pl
    group by pl.PostId
),
close_events as (
    select
        ph.PostId,
        min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as FirstClosedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate else null end) as LastClosedDate,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseCount,
        sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenCount,
        max(case when ph.PostHistoryTypeId = 10 and ph.Comment ~ '^[0-9]+$' then ph.Comment else null end) as LastCloseReasonIdRaw
    from PostHistory ph
    where ph.PostId is not null
    group by ph.PostId
),
question_quality as (
    select
        tr.QuestionId,
        tr.Title,
        tr.CreationDate,
        tr.Score,
        tr.ViewCount,
        tr.AnswerCount,
        ts.TagCount,
        ts.TagListCsv,
        case when ts.HasSQLTag is not null then 1 else 0 end as HasSQLTag,
        va.UpvoteCnt,
        va.DownvoteCnt,
        va.FavoriteCnt,
        va.BountyStartAmt,
        va.BountyCloseAmt,
        va.TotalVotes,
        ca.CommentCnt,
        ca.LastCommentDate,
        ca.PosCommentCnt,
        ca.NegCommentCnt,
        ca.MaxCommentLen,
        la.LinkedCnt,
        la.DuplicateCnt,
        la.TotalLinks,
        coalesce(la.HasDuplicateMark,false) as HasDuplicateMark,
        ce.FirstClosedDate,
        ce.LastClosedDate,
        ce.CloseCount,
        ce.ReopenCount,
        case when ce.LastCloseReasonIdRaw = '' then null else ce.LastCloseReasonIdRaw end as LastCloseReasonIdRaw,
        dense_rank() over (order by coalesce(va.UpvoteCnt,0) - coalesce(va.DownvoteCnt,0) desc, tr.ViewCount desc, tr.Score desc) as PopularityRank
    from top_recent tr
    left join tag_stats ts on ts.QuestionId = tr.QuestionId
    left join vote_agg va on va.PostId = tr.QuestionId
    left join comment_agg ca on ca.PostId = tr.QuestionId
    left join link_agg la on la.PostId = tr.QuestionId
    left join close_events ce on ce.PostId = tr.QuestionId
),
best_answers as (
    select
        a.QuestionId,
        a.AnswerId as BestByScoreAnswerId,
        a.AnswerOwnerId as BestByScoreOwnerId,
        a.AnswerScore as BestByScore,
        a.AnswerCreationDate as BestByScoreCreated
    from answers a
    where a.rn_best_by_score = 1
),
accepted_enriched as (
    select
        aa.QuestionId,
        aa.AcceptedAnswerId,
        a.AnswerOwnerId as AcceptedOwnerId,
        a.AnswerScore as AcceptedScore,
        a.AnswerCreationDate as AcceptedCreated
    from accepted_answers aa
    left join answers a
      on a.AnswerId = aa.AcceptedAnswerId
),
owner_info as (
    select
        tr.QuestionId,
        ue.UserId as OwnerUserId,
        ue.DisplayName as OwnerName,
        ue.Reputation as OwnerRep,
        ue.Location as OwnerLocation,
        ue.NetVotes as OwnerNetVotes,
        ue.BadgeScore as OwnerBadgeScore,
        ue.GoldCnt as OwnerGold,
        ue.SilverCnt as OwnerSilver,
        ue.BronzeCnt as OwnerBronze
    from top_recent tr
    left join user_enrichment ue on ue.UserId = tr.OwnerUserId
),
answerer_info as (
    select
        ba.QuestionId,
        ue_best.UserId as BestUserId,
        ue_best.DisplayName as BestUserName,
        ue_best.Reputation as BestUserRep,
        ue_best.BadgeScore as BestUserBadgeScore,
        ue_acc.UserId as AccUserId,
        ue_acc.DisplayName as AccUserName,
        ue_acc.Reputation as AccUserRep,
        ue_acc.BadgeScore as AccUserBadgeScore
    from best_answers ba
    left join accepted_enriched ae on ae.QuestionId = ba.QuestionId
    left join user_enrichment ue_best on ue_best.UserId = ba.BestByScoreOwnerId
    left join user_enrichment ue_acc on ue_acc.UserId = ae.AcceptedOwnerId
),
question_flags as (
    select
        qq.QuestionId,
        case when qq.HasDuplicateMark or qq.DuplicateCnt > 0 then 1 else 0 end as IsDuplicate,
        case when qq.FirstClosedDate is not null then 1 else 0 end as IsClosed,
        case when qq.Score < 0 or coalesce(qq.DownvoteCnt,0) > coalesce(qq.UpvoteCnt,0) then 1 else 0 end as IsControversial,
        case when qq.PopularityRank <= 100 then 1 else 0 end as IsTop100,
        case when qq.TagCount = 0 or qq.TagCount is null then 1 else 0 end as HasNoTags
    from question_quality qq
),
rankings as (
    select
        qq.QuestionId,
        row_number() over (order by coalesce(qq.ViewCount,0) desc) as rn_views,
        row_number() over (order by coalesce(qq.Score,0) desc) as rn_score,
        row_number() over (order by coalesce(qq.FavoriteCnt,0) desc) as rn_favs,
        row_number() over (order by coalesce(qq.TotalVotes,0) desc) as rn_votes,
        row_number() over (order by coalesce(qq.CommentCnt,0) desc) as rn_comments
    from question_quality qq
),
final_set as (
    select
        qq.QuestionId,
        qq.Title,
        qq.CreationDate,
        qq.Score,
        qq.ViewCount,
        qq.AnswerCount,
        qq.TagCount,
        qq.TagListCsv,
        qq.HasSQLTag,
        qq.UpvoteCnt,
        qq.DownvoteCnt,
        qq.FavoriteCnt,
        qq.BountyStartAmt,
        qq.BountyCloseAmt,
        qq.TotalVotes,
        qq.CommentCnt,
        qq.LastCommentDate,
        qq.PosCommentCnt,
        qq.NegCommentCnt,
        qq.MaxCommentLen,
        qq.LinkedCnt,
        qq.DuplicateCnt,
        qq.TotalLinks,
        qq.HasDuplicateMark,
        qq.FirstClosedDate,
        qq.LastClosedDate,
        qq.CloseCount,
        qq.ReopenCount,
        case when qq.LastCloseReasonIdRaw = '' then null else qq.LastCloseReasonIdRaw end as LastCloseReasonId,
        qq.PopularityRank,
        oi.OwnerUserId,
        oi.OwnerName,
        oi.OwnerRep,
        oi.OwnerLocation,
        oi.OwnerNetVotes,
        oi.OwnerBadgeScore,
        oi.OwnerGold,
        oi.OwnerSilver,
        oi.OwnerBronze,
        ba.BestByScoreAnswerId,
        ba.BestByScore,
        ba.BestByScoreCreated,
        ae.AcceptedAnswerId,
        ae.AcceptedScore,
        ae.AcceptedCreated,
        ai.BestUserId,
        ai.BestUserName,
        ai.BestUserRep,
        ai.BestUserBadgeScore,
        ai.AccUserId,
        ai.AccUserName,
        ai.AccUserRep,
        ai.AccUserBadgeScore,
        qf.IsDuplicate,
        qf.IsClosed,
        qf.IsControversial,
        qf.IsTop100,
        qf.HasNoTags,
        r.rn_views,
        r.rn_score,
        r.rn_favs,
        r.rn_votes,
        r.rn_comments
    from question_quality qq
    left join owner_info oi on oi.QuestionId = qq.QuestionId
    left join best_answers ba on ba.QuestionId = qq.QuestionId
    left join accepted_enriched ae on ae.QuestionId = qq.QuestionId
    left join answerer_info ai on ai.QuestionId = qq.QuestionId
    left join question_flags qf on qf.QuestionId = qq.QuestionId
    left join rankings r on r.QuestionId = qq.QuestionId
),
normalized as (
    select
        fs.*,
        case when fs.ViewCount is null then null
             else (cast(fs.ViewCount as numeric) / nullif(max(fs.ViewCount) over (), 0)) end as ViewPct,
        case when fs.Score is null then null
             else (cast(fs.Score as numeric) / nullif(max(fs.Score) over (), 0)) end as ScorePct,
        case when fs.TotalVotes is null then null
             else (cast(fs.TotalVotes as numeric) / nullif(max(fs.TotalVotes) over (), 0)) end as VotePct
    from final_set fs
),
scored as (
    select
        n.*,
        (
            coalesce(n.ViewPct,0)*0.35 +
            coalesce(n.ScorePct,0)*0.30 +
            coalesce(n.VotePct,0)*0.15 +
            (case when n.HasSQLTag = 1 then 0.05 else 0 end) +
            (case when n.IsTop100 = 1 then 0.05 else 0 end) +
            (case when n.IsDuplicate = 1 then -0.10 else 0 end) +
            (case when n.IsClosed = 1 then -0.10 else 0 end) +
            least(cast(coalesce(n.OwnerBadgeScore,0) as numeric) / 500.0, 0.10)
        ) as PerfCompositeScore
    from normalized n
),
dupe_clusters as (
    select
        s.QuestionId,
        coalesce(pl.RelatedPostId, s.QuestionId) as ClusterKey
    from scored s
    left join PostLinks pl
      on pl.PostId = s.QuestionId and pl.LinkTypeId = 3
),
cluster_rank as (
    select
        s.QuestionId,
        dc.ClusterKey,
        row_number() over (partition by dc.ClusterKey order by s.PerfCompositeScore desc, s.PopularityRank asc, s.QuestionId asc) as rn_in_cluster
    from scored s
    left join dupe_clusters dc on dc.QuestionId = s.QuestionId
),
filtered as (
    select s.*
    from scored s
    left join cluster_rank cr on cr.QuestionId = s.QuestionId
    where coalesce(cr.rn_in_cluster,1) = 1
),
final_ordered as (
    select
        f.QuestionId,
        f.Title,
        f.CreationDate,
        f.Score,
        f.ViewCount,
        f.AnswerCount,
        f.TagListCsv,
        f.HasSQLTag,
        f.UpvoteCnt,
        f.DownvoteCnt,
        f.FavoriteCnt,
        f.BountyStartAmt,
        f.BountyCloseAmt,
        f.TotalVotes,
        f.CommentCnt,
        f.LinkedCnt,
        f.DuplicateCnt,
        f.HasDuplicateMark,
        f.FirstClosedDate,
        f.LastClosedDate,
        f.CloseCount,
        f.ReopenCount,
        f.LastCloseReasonId,
        f.PopularityRank,
        f.OwnerUserId,
        f.OwnerName,
        f.OwnerRep,
        f.OwnerBadgeScore,
        f.BestByScoreAnswerId,
        f.BestByScore,
        f.AcceptedAnswerId,
        f.AcceptedScore,
        f.BestUserId,
        f.BestUserRep,
        f.AccUserId,
        f.AccUserRep,
        f.IsDuplicate,
        f.IsClosed,
        f.IsControversial,
        f.IsTop100,
        f.HasNoTags,
        f.rn_views,
        f.rn_score,
        f.rn_favs,
        f.rn_votes,
        f.rn_comments,
        f.ViewPct,
        f.ScorePct,
        f.VotePct,
        f.PerfCompositeScore,
        row_number() over (
            order by f.PerfCompositeScore desc,
                     f.PopularityRank asc,
                     f.ViewCount desc,
                     f.Score desc,
                     f.QuestionId desc
        ) as final_rn
    from filtered f
)
select
    fo.QuestionId,
    fo.Title,
    fo.CreationDate,
    fo.Score,
    fo.ViewCount,
    fo.AnswerCount,
    fo.TagListCsv,
    fo.HasSQLTag,
    fo.UpvoteCnt,
    fo.DownvoteCnt,
    fo.FavoriteCnt,
    fo.BountyStartAmt,
    fo.BountyCloseAmt,
    fo.TotalVotes,
    fo.CommentCnt,
    fo.LinkedCnt,
    fo.DuplicateCnt,
    fo.HasDuplicateMark,
    fo.FirstClosedDate,
    fo.LastClosedDate,
    fo.CloseCount,
    fo.ReopenCount,
    fo.LastCloseReasonId,
    fo.PopularityRank,
    fo.OwnerUserId,
    fo.OwnerName,
    fo.OwnerRep,
    fo.OwnerBadgeScore,
    fo.BestByScoreAnswerId,
    fo.BestByScore,
    fo.AcceptedAnswerId,
    fo.AcceptedScore,
    fo.BestUserId,
    fo.BestUserRep,
    fo.AccUserId,
    fo.AccUserRep,
    fo.IsDuplicate,
    fo.IsClosed,
    fo.IsControversial,
    fo.IsTop100,
    fo.HasNoTags,
    fo.rn_views,
    fo.rn_score,
    fo.rn_favs,
    fo.rn_votes,
    fo.rn_comments,
    fo.ViewPct,
    fo.ScorePct,
    fo.VotePct,
    fo.PerfCompositeScore
from final_ordered fo
where fo.final_rn <= 500;