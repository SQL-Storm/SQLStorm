-- {"query": "1057.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1546} 
with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(coalesce(b.Class,0)) as BadgeWeight
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostScores as (
    select
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Title,
        p.Score,
        p.ViewCount,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as rn,
        rank() over (partition by p.PostTypeId order by p.Score desc) as score_rank
    from Posts p
    where p.PostTypeId in (1,2) and p.Score is not null
),
TopUserPosts as (
    select
        ps.*,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ubc.BadgeWeight
    from PostScores ps
    left join UserBadgeCounts ubc on ubc.UserId = ps.OwnerUserId
    where ps.rn <= 5
),
DuplicatePostCounts as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate link type
    group by pl.PostId
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10 -- Post Closed
    group by ph.PostId, crt.Name
),
UserScoreStats as (
    select
        p.OwnerUserId,
        count(*) as TotalPosts,
        avg(p.Score) as AvgScore,
        sum(p.ViewCount) as TotalViews,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
RecentComments as (
    select
        c.PostId,
        c.UserId,
        c.CreationDate,
        c.Text,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as rn
    from Comments c
),
TopComments as (
    select
        rc.PostId,
        rc.UserId,
        rc.CreationDate,
        rc.Text
    from RecentComments rc
    where rc.rn <= 3
),
HighlyActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        coalesce(ubc.GoldBadges,0) as GoldBadges,
        coalesce(ubc.SilverBadges,0) as SilverBadges,
        coalesce(ubc.BronzeBadges,0) as BronzeBadges,
        rank() over (order by u.Reputation desc, u.Views desc) as ReputationRank
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    where u.Reputation > 1000
),
UserRecentPosts as (
    select
        p.OwnerUserId,
        max(p.CreationDate) as LastPostDate
    from Posts p
    group by p.OwnerUserId
),
CombinedUserActivity as (
    select
        hau.*,
        urp.LastPostDate
    from HighlyActiveUsers hau
    left join UserRecentPosts urp on urp.OwnerUserId = hau.Id
)
select
    tsp.UserId,
    tsp.DisplayName as PostOwner,
    tsp.PostId,
    tsp.PostTypeId,
    coalesce(tsp.Title, '[No Title]') as PostTitle,
    tsp.Score,
    tsp.ViewCount,
    tsp.Tags,
    coalesce(dpc.DuplicateCount, 0) as DuplicateCount,
    coalesce(pcr.CloseReason, 'None') as LastCloseReason,
    coalesce(pcr.CloseCount, 0) as CloseCount,
    tsp.GoldBadges,
    tsp.SilverBadges,
    tsp.BronzeBadges,
    us.AvgScore,
    us.TotalViews,
    us.QuestionCount,
    us.AnswerCount,
    tc.Text as LatestCommentText,
    tc.CreationDate as LatestCommentDate,
    cua.Reputation,
    cua.Views,
    cua.UpVotes,
    cua.DownVotes,
    cua.GoldBadges as UserGoldBadges,
    cua.SilverBadges as UserSilverBadges,
    cua.BronzeBadges as UserBronzeBadges,
    cua.LastPostDate,
    (tsp.Score * 1.0 / nullif(us.AvgScore,0)) as ScoreToAvgRatio,
    case 
        when tsp.Tags is null or trim(tsp.Tags) = '' then 'No Tags' 
        else array_to_string(string_to_array(substring(tsp.Tags, 2, length(tsp.Tags) - 2), '><'), ', ') 
    end as ParsedTags,
    concat_ws(' / ', 
        coalesce(tsp.Title, '[No Title]'), 
        'Score: '||tsp.Score,
        'Views: '||tsp.ViewCount,
        'Duplicates: '||coalesce(dpc.DuplicateCount, 0)
    ) as PostSummary
from TopUserPosts tsp
left join DuplicatePostCounts dpc on dpc.PostId = tsp.PostId
left join (
    select distinct on (ph.PostId) ph.PostId, crt.Name as CloseReason, ph_c.CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    join (
        select PostId, count(*) as CloseCount
        from PostHistory
        where PostHistoryTypeId = 10
        group by PostId
    ) ph_c on ph.PostId = ph_c.PostId
    where ph.PostHistoryTypeId = 10
    order by ph.PostId, ph.CreationDate desc
) pcr on pcr.PostId = tsp.PostId
left join UserScoreStats us on us.OwnerUserId = tsp.UserId
left join TopComments tc on tc.PostId = tsp.PostId
left join CombinedUserActivity cua on cua.Id = tsp.UserId
where tsp.Score > (select avg(Score) from Posts where PostTypeId = tsp.PostTypeId)
order by tsp.UserId, tsp.Score desc, tsp.PostId
limit 100;