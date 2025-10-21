-- {"query": "8044.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3223} 
with recursive tag_questions as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        coalesce(nullif(p.Title,''), '[no title]') as Title,
        string_to_array(substring(p.Tags, 2, greatest(length(p.Tags)-2,0)), '><') as tag_array
    from Posts p
    where p.PostTypeId = 1
),
user_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate as UserCreationDate,
        u.Location,
        u.WebsiteUrl,
        u.UpVotes,
        u.DownVotes,
        u.Views as ProfileViews,
        coalesce(nullif(u.DisplayName,''), concat('user#', u.Id::varchar)) as SafeDisplayName
    from Users u
),
answer_stats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        count(*) filter (where a.Score > 0) as PositiveAnswers,
        max(a.Score) as MaxAnswerScore,
        percentile_cont(0.5) within group (order by a.Score) as MedianAnswerScore
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
),
comment_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(coalesce(c.Score,0)) as CommentScoreSum,
        max(c.Score) as MaxCommentScore,
        min(c.Score) as MinCommentScore,
        string_agg(distinct left(coalesce(c.UserDisplayName, ''), 20), ' | ') as CommenterSamples
    from Comments c
    group by c.PostId
),
vote_agg as (
    select
        v.PostId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotes,
        count(*) filter (where v.VoteTypeId = 3) as DownVotes,
        count(*) filter (where v.VoteTypeId = 5) as Favorites,
        sum(coalesce(v.BountyAmount,0)) as BountyTotal,
        max(v.CreationDate) as LastVoteDate
    from Votes v
    group by v.PostId
),
dup_links as (
    select
        pl.PostId as DuplicateOf,
        pl.RelatedPostId as CanonicalId,
        count(*) as DupLinkCount,
        min(pl.CreationDate) as FirstDupLinkDate
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId, pl.RelatedPostId
),
closed_reasons as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastCloseEvent,
        max(case when ph.PostHistoryTypeId = 10 then try_cast(ph.Comment as int) end) as CloseReasonId
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11)
    group by ph.PostId
),
badge_agg as (
    select
        b.UserId,
        count(*) as BadgeCount,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        min(b.Date) as FirstBadgeDate,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
tag_explode as (
    select
        tq.QuestionId,
        unnest(tq.tag_array) as tagname
    from tag_questions tq
),
top_tags as (
    select
        te.QuestionId,
        te.tagname,
        row_number() over (partition by te.QuestionId order by t.Count desc nulls last, te.tagname) as rn,
        t.Count as TagGlobalCount
    from tag_explode te
    left join Tags t on lower(t.TagName) = lower(te.tagname)
),
accepted_answer_latency as (
    select
        q.Id as QuestionId,
        q.CreationDate as QuestionDate,
        a.Id as AcceptedAnswerId,
        a.CreationDate as AcceptedDate,
        extract(epoch from (a.CreationDate - q.CreationDate))::bigint as AcceptLatencySeconds
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1
),
edits_cte as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditEvents,
        max(ph.CreationDate) as LastEditEventDate
    from PostHistory ph
    group by ph.PostId
),
question_engagement as (
    select
        tq.QuestionId,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(v.Favorites,0) as Favorites,
        coalesce(ca.CommentCount,0) as CommentCount,
        coalesce(ca.CommentScoreSum,0) as CommentScoreSum
    from tag_questions tq
    left join vote_agg v on v.PostId = tq.QuestionId
    left join comment_agg ca on ca.PostId = tq.QuestionId
),
score_z as (
    select
        tq.QuestionId,
        tq.Score,
        avg(tq.Score) over () as avg_score,
        stddev_pop(tq.Score) over () as std_score_pop
    from tag_questions tq
),
question_rank as (
    select
        qe.*,
        s.avg_score,
        s.std_score_pop,
        case
            when s.std_score_pop > 0 then (coalesce((select Score from tag_questions t where t.QuestionId = qe.QuestionId),0) - s.avg_score)/s.std_score_pop
            else 0
        end as ScoreZ
    from question_engagement qe
    join score_z s on s.QuestionId = qe.QuestionId
),
owner_summary as (
    select
        tq.QuestionId,
        ua.UserId,
        ua.SafeDisplayName,
        ua.Reputation,
        ua.Location,
        ua.UpVotes as OwnerUpVotes,
        ua.DownVotes as OwnerDownVotes,
        ua.ProfileViews,
        ba.BadgeCount,
        ba.GoldBadges,
        ba.SilverBadges,
        ba.BronzeBadges
    from tag_questions tq
    left join user_activity ua on ua.UserId = tq.OwnerUserId
    left join badge_agg ba on ba.UserId = ua.UserId
),
win_metrics as (
    select
        tq.QuestionId,
        tq.CreationDate,
        tq.ViewCount,
        row_number() over (order by tq.ViewCount desc nulls last, tq.CreationDate) as rn_views,
        ntile(10) over (order by tq.ViewCount desc nulls last) as view_decile,
        dense_rank() over (order by tq.Score desc nulls last) as score_rank_dense,
        sum(coalesce(tq.Score,0)) over (order by tq.CreationDate rows between unbounded preceding and current row) as cumulative_score_over_time
    from tag_questions tq
),
heavy_predicate as (
    select
        tq.QuestionId
    from tag_questions tq
    where
        -- complicated predicate mixing string ops, null logic, math, date ranges
        (
            position('python' in lower(coalesce(tq.Tags,''))) > 0
            or position('java' in lower(coalesce(tq.Tags,''))) > 0
            or array_length(tq.tag_array,1) >= 5
        )
        and coalesce(tq.ViewCount,0) >= 0
        and coalesce(tq.Score,0) between -5 and 100000
        and extract(year from tq.CreationDate) >= 2008
),
joined as (
    select
        tq.QuestionId,
        tq.Title,
        tq.CreationDate,
        tq.Score,
        tq.ViewCount,
        left(coalesce(tq.Tags,'[]'), 200) as TagsPreview,
        os.SafeDisplayName as OwnerName,
        os.Reputation as OwnerReputation,
        os.Location as OwnerLocation,
        os.BadgeCount,
        os.GoldBadges,
        os.SilverBadges,
        os.BronzeBadges,
        coalesce(ans.AnswerCount,0) as AnswerCount,
        coalesce(ans.PositiveAnswers,0) as PositiveAnswers,
        ans.MaxAnswerScore,
        ans.MedianAnswerScore,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(v.Favorites,0) as Favorites,
        v.BountyTotal,
        v.LastVoteDate,
        ca.CommentCount,
        ca.CommentScoreSum,
        ca.MaxCommentScore,
        ed.EditEvents,
        ed.LastEditEventDate,
        cr.CloseReasonId,
        cr.LastCloseEvent,
        al.AcceptedAnswerId,
        al.AcceptLatencySeconds,
        wm.rn_views,
        wm.view_decile,
        wm.score_rank_dense,
        wm.cumulative_score_over_time,
        qr.ScoreZ
    from tag_questions tq
    left join owner_summary os on os.QuestionId = tq.QuestionId
    left join answer_stats ans on ans.QuestionId = tq.QuestionId
    left join vote_agg v on v.PostId = tq.QuestionId
    left join comment_agg ca on ca.PostId = tq.QuestionId
    left join edits_cte ed on ed.PostId = tq.QuestionId
    left join closed_reasons cr on cr.PostId = tq.QuestionId
    left join accepted_answer_latency al on al.QuestionId = tq.QuestionId
    left join win_metrics wm on wm.QuestionId = tq.QuestionId
    left join question_rank qr on qr.QuestionId = tq.QuestionId
    where tq.QuestionId in (select QuestionId from heavy_predicate)
),
top2_tags as (
    select
        tt.QuestionId,
        max(case when tt.rn = 1 then tt.tagname end) as TopTag1,
        max(case when tt.rn = 2 then tt.tagname end) as TopTag2,
        max(case when tt.rn = 1 then tt.TagGlobalCount end) as TopTag1GlobalCount,
        max(case when tt.rn = 2 then tt.TagGlobalCount end) as TopTag2GlobalCount
    from top_tags tt
    where tt.rn <= 2
    group by tt.QuestionId
),
dupe_summary as (
    select
        d.DuplicateOf as QuestionId,
        count(*) as DuplicatePairs,
        min(d.FirstDupLinkDate) as FirstDupDate,
        string_agg(distinct d.CanonicalId::varchar, ',') as CanonicalIds
    from dup_links d
    group by d.DuplicateOf
),
final_union as (
    select
        j.*,
        t2.TopTag1,
        t2.TopTag2,
        t2.TopTag1GlobalCount,
        t2.TopTag2GlobalCount,
        ds.DuplicatePairs,
        ds.FirstDupDate,
        ds.CanonicalIds
    from joined j
    left join top2_tags t2 on t2.QuestionId = j.QuestionId
    left join dupe_summary ds on ds.QuestionId = j.QuestionId
    where coalesce(j.AnswerCount,0) >= 0
    union all
    -- bring in a second set: high-score but low-views outliers for contrast
    select
        j.*,
        t2.TopTag1,
        t2.TopTag2,
        t2.TopTag1GlobalCount,
        t2.TopTag2GlobalCount,
        ds.DuplicatePairs,
        ds.FirstDupDate,
        ds.CanonicalIds
    from joined j
    left join top2_tags t2 on t2.QuestionId = j.QuestionId
    left join dupe_summary ds on ds.QuestionId = j.QuestionId
    where j.Score >= (select avg(Score) + 2*coalesce(stddev_pop(Score),0) from tag_questions)
      and coalesce(j.ViewCount,0) < (select percentile_cont(0.25) within group (order by coalesce(ViewCount,0)) from tag_questions)
)
select
    f.QuestionId,
    f.Title,
    f.OwnerName,
    f.OwnerReputation,
    f.OwnerLocation,
    f.BadgeCount,
    f.GoldBadges,
    f.SilverBadges,
    f.BronzeBadges,
    f.Score,
    f.ViewCount,
    f.AnswerCount,
    f.PositiveAnswers,
    f.MaxAnswerScore,
    f.MedianAnswerScore,
    f.UpVotes,
    f.DownVotes,
    f.Favorites,
    f.BountyTotal,
    f.CommentCount,
    f.CommentScoreSum,
    f.MaxCommentScore,
    f.EditEvents,
    f.LastEditEventDate,
    f.CloseReasonId,
    f.LastCloseEvent,
    f.AcceptedAnswerId,
    f.AcceptLatencySeconds,
    f.rn_views,
    f.view_decile,
    f.score_rank_dense,
    round(coalesce(f.ScoreZ,0)::numeric, 3) as ScoreZ,
    f.cumulative_score_over_time,
    coalesce(f.TopTag1,'') as TopTag1,
    coalesce(f.TopTag2,'') as TopTag2,
    f.TopTag1GlobalCount,
    f.TopTag2GlobalCount,
    coalesce(f.DuplicatePairs,0) as DuplicatePairs,
    f.FirstDupDate,
    f.CanonicalIds,
    case
        when f.AcceptLatencySeconds is null then 'unaccepted'
        when f.AcceptLatencySeconds < 3600 then 'fast-accept'
        when f.AcceptLatencySeconds < 86400 then 'same-day'
        when f.AcceptLatencySeconds < 604800 then 'within-week'
        else 'slow-accept'
    end as AcceptSpeedBucket,
    case
        when coalesce(f.Favorites,0) > 0 then 'bookmarked'
        when coalesce(f.UpVotes,0) >= 5 and coalesce(f.DownVotes,0) = 0 then 'popular'
        when coalesce(f.UpVotes,0) = 0 and coalesce(f.DownVotes,0) > 0 then 'controversial'
        else 'normal'
    end as PopularityClass,
    left(f.TagsPreview, 200) as TagsPreview,
    now() as BenchmarkRunAt
from final_union f
where
    -- final filter to create some workload variance
    (f.TopTag1 is not null or f.TopTag2 is not null)
    and (f.DuplicatePairs is null or f.DuplicatePairs < 50)
    and (f.Score between -10 and 100000)
order by
    coalesce(f.ScoreZ,0) desc nulls last,
    f.ViewCount desc nulls last,
    f.Score desc,
    f.CreationDate
limit 500;