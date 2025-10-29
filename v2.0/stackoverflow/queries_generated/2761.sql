-- {"query": "2761.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1050} 
with RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn_score_view,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as dr_score
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2)
), AnswerScores as (
    select 
        a.ParentId,
        count(*) as AnswerCount,
        sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
        sum(a.Score) as TotalAnswerScore,
        max(a.Score) as MaxAnswerScore
    from Posts a
    where a.PostTypeId = 2
    group by a.ParentId
), CloseReasonsCount as (
    select
        ph.PostId,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseVotes,
        max(case when ph.PostHistoryTypeId = 10 then cast(ph.Comment as int) else null end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
), UserBadgeStats as (
    select
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
), UserVotesSummary as (
    select
        v.UserId,
        count(*) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(*) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        count(*) filter (where v.VoteTypeId = 15) as ModeratorReviews
    from Votes v
    group by v.UserId
), TopTags as (
    select 
        t.TagName,
        t.Count,
        p.Id as ExcerptPostId,
        p.Title as ExcerptTitle,
        p.Body as ExcerptBody
    from Tags t
    left join Posts p on t.ExcerptPostId = p.Id
    where t.Count > 1000
), PostsWithComments as (
    select 
        p.Id,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
)
select distinct
    rp.Id as PostId,
    rp.PostTypeId,
    rp.Title,
    coalesce(rp.Tags, '[No Tags]') as Tags,
    rp.CreationDate,
    rp.OwnerUserId,
    rp.OwnerName,
    rp.Score,
    rp.ViewCount,
    rp.AnswerCount,
    rp.FavoriteCount,
    coalesce(ans.AnswerCount,0) as AnswerTotal,
    coalesce(ans.PositiveAnswers,0) as PositiveAnswerCount,
    coalesce(ans.TotalAnswerScore,0) as TotalAnswerScores,
    coalesce(ans.MaxAnswerScore,0) as MaxAnswerScore,
    crc.CloseVotes,
    crt.Name as CloseReason,
    ub.TotalBadges,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LastBadgeDate,
    uv.UpVotesGiven,
    uv.DownVotesGiven,
    uv.ModeratorReviews,
    pc.CommentCount,
    pc.LastCommentDate,
    concat(
        'Top Tags: ', 
        string_agg(distinct tt.TagName, ', ' ORDER BY tt.Count DESC)
        ) over () as PopularTags
from RankedPosts rp
left join AnswerScores ans on rp.Id = ans.ParentId
left join CloseReasonsCount crc on rp.Id = crc.PostId
left join CloseReasonTypes crt on crt.Id = crc.CloseReasonId
left join UserBadgeStats ub on ub.UserId = rp.OwnerUserId
left join UserVotesSummary uv on uv.UserId = rp.OwnerUserId
left join PostsWithComments pc on rp.Id = pc.Id
left join TopTags tt on rp.Tags like concat('%<', tt.TagName, '>%')
where rp.rn_score_view <= 100
  and ((rp.PostTypeId = 1 and crc.CloseVotes is null) or rp.PostTypeId = 2)
order by rp.PostTypeId, rp.Score desc, rp.ViewCount desc
limit 200;