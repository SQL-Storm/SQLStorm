with
q_posts as (
    select p.Id as QuestionId,
           p.OwnerUserId as QOwnerId,
           p.CreationDate as QCreated,
           p.Score as QScore,
           p.ViewCount as QViews,
           p.Title,
           p.Tags,
           p.AcceptedAnswerId
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
q_activity as (
    select q.QuestionId,
           count(distinct c.Id) as CommentCount,
           coalesce(sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end),0) as NetVotes,
           max(coalesce(c.CreationDate, v.CreationDate, q.QCreated)) as LastActivity
    from q_posts q
    left join Comments c on c.PostId = q.QuestionId
    left join Votes v on v.PostId = q.QuestionId
    group by q.QuestionId, q.QCreated
),
answers_ranked as (
    select
        a.QuestionId,
        a.AnswerId,
        a.AOwnerId,
        a.AScore,
        a.ACreated,
        row_number() over (partition by a.QuestionId order by a.AScore desc, a.ACreated asc) as rn_score,
        row_number() over (partition by a.QuestionId order by a.ACreated asc) as rn_first,
        avg(a.AScore) over (partition by a.QuestionId) as avg_answer_score,
        count(*) over (partition by a.QuestionId) as answer_count
    from a_posts a
),
accepted_vs_best as (
    select
        q.QuestionId,
        q.AcceptedAnswerId,
        ar.AnswerId as TopScoreAnswerId,
        ar.AScore as TopScore,
        ar.avg_answer_score,
        ar.answer_count,
        min(case when ar.AnswerId = q.AcceptedAnswerId then ar.rn_first end) over (partition by q.QuestionId) as accepted_rank_by_time,
        min(case when ar.AnswerId = q.AcceptedAnswerId then ar.rn_score end) over (partition by q.QuestionId) as accepted_rank_by_score
    from q_posts q
    left join answers_ranked ar
      on ar.QuestionId = q.QuestionId
),
tag_split as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
    from q_posts q
    where q.Tags is not null
),
tag_stats as (
    select
        ts.tag,
        count(*) as tag_q_count,
        avg(q.QScore) as tag_avg_q_score,
        percentile_cont(0.9) within group (order by q.QViews) as p90_views
    from tag_split ts
    join q_posts q on q.QuestionId = ts.QuestionId
    group by ts.tag
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        coalesce(nullif(u.Location, ''), 'Unknown') as LocationNorm,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(b.Id) as TotalBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, LocationNorm
),
q_user as (
    select
        q.QuestionId,
        q.QOwnerId,
        us.Reputation as QOwnerRep,
        us.TotalBadges as QOwnerBadges
    from q_posts q
    left join user_stats us on us.UserId = q.QOwnerId
),
dupe_links as (
    select
        pl.PostId as QuestionId,
        count(case when pl.LinkTypeId = 3 then 1 end) as DuplicateLinks,
        count(case when pl.LinkTypeId = 1 then 1 end) as RegularLinks
    from PostLinks pl
    group by pl.PostId
),
close_events as (
    select
        ph.PostId as QuestionId,
        min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstClosedDate,
        max(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as LastReopenedDate,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as CloseVotesEvents,
        count(case when ph.PostHistoryTypeId = 11 then 1 end) as ReopenEvents,
        count(case when ph.PostHistoryTypeId in (12,13) then 1 end) as DeleteUndeleteEvents,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as integer) end) as LastCloseReasonId
    from PostHistory ph
    group by ph.PostId
),
close_reason_names as (
    select
        crt.Id as CloseReasonId,
        crt.Name as CloseReasonName
    from CloseReasonTypes crt
),
question_quality as (
    select
        q.QuestionId,
        q.Title,
        q.QScore,
        q.QViews,
        qa.CommentCount,
        qa.NetVotes,
        qa.LastActivity,
        coalesce(du.DuplicateLinks,0) as DuplicateLinks,
        coalesce(du.RegularLinks,0) as RegularLinks,
        coalesce(c.FirstClosedDate, timestamp '1900-01-01') as FirstClosedDate,
        c.LastReopenedDate,
        c.CloseVotesEvents,
        c.ReopenEvents,
        c.DeleteUndeleteEvents,
        crn.CloseReasonName,
        qu.QOwnerRep,
        qu.QOwnerBadges
    from q_posts q
    left join q_activity qa on qa.QuestionId = q.QuestionId
    left join dupe_links du on du.QuestionId = q.QuestionId
    left join close_events c on c.QuestionId = q.QuestionId
    left join close_reason_names crn on crn.CloseReasonId = c.LastCloseReasonId
    left join q_user qu on qu.QuestionId = q.QuestionId
),
tag_enriched as (
    select
        ts.tag,
        ts.tag_q_count,
        ts.tag_avg_q_score,
        ts.p90_views,
        t.IsModeratorOnly,
        t.IsRequired
    from tag_stats ts
    left join Tags t on lower(t.TagName) = lower(ts.tag)
),
question_tag_agg as (
    select
        ts.QuestionId,
        count(*) as TagCount,
        sum(case when te.IsModeratorOnly then 1 else 0 end) as ModOnlyTags,
        sum(case when te.IsRequired then 1 else 0 end) as RequiredTags,
        avg(te.tag_avg_q_score) as AvgTagAvgScore,
        max(te.p90_views) as MaxTagP90Views,
        string_agg(ts.tag, '|' order by ts.tag) as TagList
    from tag_split ts
    left join tag_enriched te on te.tag = ts.tag
    group by ts.QuestionId
),
answer_delta as (
    select
        q.QuestionId,
        coalesce(avb.TopScore, 0) - coalesce(avg(ar.AScore) filter (where ar.QuestionId = q.QuestionId), 0) as TopMinusAvgAnswerScore
    from q_posts q
    left join accepted_vs_best avb on avb.QuestionId = q.QuestionId
    left join answers_ranked ar on ar.QuestionId = q.QuestionId
    group by q.QuestionId, avb.TopScore
),
view_bins as (
    select
        qq.QuestionId,
        case
            when qq.QViews is null then 'unknown'
            when qq.QViews < 100 then 'vlow'
            when qq.QViews < 1000 then 'low'
            when qq.QViews < 10000 then 'med'
            when qq.QViews < 100000 then 'high'
            else 'vhigh'
        end as ViewBucket
    from question_quality qq
),
final_scored as (
    select
        qq.QuestionId,
        qq.Title,
        qq.QScore,
        qq.QViews,
        qa.TagCount,
        qa.ModOnlyTags,
        qa.RequiredTags,
        qa.AvgTagAvgScore,
        qa.MaxTagP90Views,
        qa.TagList,
        qq.CommentCount,
        qq.NetVotes,
        qq.LastActivity,
        qq.DuplicateLinks,
        qq.RegularLinks,
        qq.FirstClosedDate,
        qq.LastReopenedDate,
        qq.CloseVotesEvents,
        qq.ReopenEvents,
        qq.DeleteUndeleteEvents,
        coalesce(qq.CloseReasonName, 'None') as CloseReasonName,
        qq.QOwnerRep,
        qq.QOwnerBadges,
        coalesce(avb.accepted_rank_by_time, 9999) as AcceptedRankByTime,
        coalesce(avb.accepted_rank_by_score, 9999) as AcceptedRankByScore,
        coalesce(avb.answer_count, 0) as AnswerCount,
        coalesce(ad.TopMinusAvgAnswerScore, 0) as TopMinusAvgAnswerScore,
        vb.ViewBucket,
        (
          coalesce(qq.QScore,0)*2
          + coalesce(qq.NetVotes,0)
          + least(coalesce(qa.TagCount,0), 5)
          + case when qq.DuplicateLinks > 0 then -5 else 0 end
          + case when qq.CloseVotesEvents > 0 then -3 else 0 end
          + case when coalesce(avb.accepted_rank_by_score,9999) = 1 then 3 else 0 end
          + case when coalesce(avb.answer_count,0) >= 3 then 2 else 0 end
          + case when vb.ViewBucket in ('high','vhigh') then 4 when vb.ViewBucket = 'med' then 2 else 0 end
          + greatest(least(coalesce(ad.TopMinusAvgAnswerScore,0), 10), -10)
        ) as CompositeScore
    from question_quality qq
    left join question_tag_agg qa on qa.QuestionId = qq.QuestionId
    left join accepted_vs_best avb on avb.QuestionId = qq.QuestionId
    left join answer_delta ad on ad.QuestionId = qq.QuestionId
    left join view_bins vb on vb.QuestionId = qq.QuestionId
),
ranked as (
    select
        fs.QuestionId,
        fs.Title,
        fs.QScore,
        fs.QViews,
        fs.TagCount,
        fs.ModOnlyTags,
        fs.RequiredTags,
        fs.AvgTagAvgScore,
        fs.MaxTagP90Views,
        fs.TagList,
        fs.CommentCount,
        fs.NetVotes,
        fs.LastActivity,
        fs.DuplicateLinks,
        fs.RegularLinks,
        fs.FirstClosedDate,
        fs.LastReopenedDate,
        fs.CloseVotesEvents,
        fs.ReopenEvents,
        fs.DeleteUndeleteEvents,
        fs.CloseReasonName,
        fs.QOwnerRep,
        fs.QOwnerBadges,
        fs.AcceptedRankByTime,
        fs.AcceptedRankByScore,
        fs.AnswerCount,
        fs.TopMinusAvgAnswerScore,
        fs.ViewBucket,
        fs.CompositeScore,
        dense_rank() over (order by fs.CompositeScore desc, fs.QViews desc, fs.QScore desc) as QualityRank,
        percent_rank() over (order by fs.CompositeScore) as CompositePercentile,
        ntile(10) over (order by fs.CompositeScore desc) as Decile
    from final_scored fs
)
select
    r.QuestionId,
    r.Title,
    r.QScore,
    r.QViews,
    r.AnswerCount,
    r.AcceptedRankByScore,
    r.AcceptedRankByTime,
    r.TagCount,
    r.TagList,
    r.ViewBucket,
    r.CloseReasonName,
    r.QOwnerRep,
    r.QOwnerBadges,
    r.CompositeScore,
    r.QualityRank,
    r.Decile,
    r.CompositePercentile,
    (
        select ph.UserDisplayName
        from PostHistory ph
        where ph.PostId = r.QuestionId
          and ph.UserDisplayName is not null
          and ph.UserDisplayName <> ''
        order by ph.CreationDate desc
        fetch first 1 row only
    ) as LastEditorName,
    coalesce(nullif(substring(r.Title from 1 for 100), ''), '(no title)') || ' [' || coalesce(r.ViewBucket,'unknown') || ']' as TitlePreview,
    avg(r.CompositeScore) over (partition by r.ViewBucket) as AvgCompositeByBucket,
    count(*) over (partition by r.CloseReasonName) as CountByCloseReason
from ranked r
where
    (r.QScore >= 0 or r.QScore is null)
    and (r.TagCount is null or r.TagCount between 1 and 5)
    and (r.CloseReasonName is null or lower(r.CloseReasonName) not like '%opinion%')
    and r.Decile <= 5
order by r.CompositeScore desc, r.QViews desc
limit 200;