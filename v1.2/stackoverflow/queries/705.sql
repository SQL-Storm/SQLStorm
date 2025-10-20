-- {"query": "705.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1229} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000 and u.Location is not null
),
RecentPosts as (
    select
        UserId,
        DisplayName,
        Reputation,
        Location,
        PostId,
        PostTypeId,
        Score,
        ViewCount,
        PostCreationDate
    from RecursiveUserActivity
    where rn <= 5
),
PostScoresAgg as (
    select
        UserId,
        PostTypeId,
        count(PostId) as PostCount,
        sum(Score) as TotalScore,
        avg(Score) as AvgScore,
        sum(ViewCount) as TotalViews
    from RecentPosts
    group by UserId, PostTypeId
),
BadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
LatestComments as (
    select
        c.PostId,
        c.UserId as CommenterId,
        c.CreationDate as CommentDate,
        c.Text as CommentText,
        row_number() over (partition by c.PostId order by c.CreationDate desc) as rn
    from Comments c
),
TopComments as (
    select
        PostId,
        CommenterId,
        CommentDate,
        substring(CommentText, 1, 50) as ShortCommentText
    from LatestComments
    where rn = 1
),
DuplicateLinks as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3
    group by pl.PostId
),
ClosedPosts as (
    select
        ph.PostId,
        max(ph.CreationDate) as LastClosedDate,
        max(c.Name) as CloseReason
    from PostHistory ph
    left join CloseReasonTypes c on cast(ph.Comment as int) = c.Id and ph.PostHistoryTypeId = 10
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserPostDetails as (
    select
        rp.UserId,
        rp.DisplayName,
        rp.Location,
        ps.PostTypeId,
        ps.PostCount,
        ps.TotalScore,
        ps.AvgScore,
        ps.TotalViews,
        coalesce(bc.GoldBadges,0) as GoldBadges,
        coalesce(bc.SilverBadges,0) as SilverBadges,
        coalesce(bc.BronzeBadges,0) as BronzeBadges
    from RecentPosts rp
    join PostScoresAgg ps on rp.UserId = ps.UserId and rp.PostTypeId = ps.PostTypeId
    left join BadgeCounts bc on rp.UserId = bc.UserId
    group by rp.UserId, rp.DisplayName, rp.Location, ps.PostTypeId, ps.PostCount, ps.TotalScore, ps.AvgScore, ps.TotalViews, bc.GoldBadges, bc.SilverBadges, bc.BronzeBadges
),
FinalResult as (
    select distinct
        upd.UserId,
        upd.DisplayName,
        upd.Location,
        pt.Name as PostType,
        upd.PostCount,
        upd.TotalScore,
        upd.AvgScore,
        upd.TotalViews,
        upd.GoldBadges,
        upd.SilverBadges,
        upd.BronzeBadges,
        coalesce(dl.DuplicateCount,0) as NumDuplicates,
        coalesce(cp.LastClosedDate, timestamp '1970-01-01') as LastClosedDate,
        coalesce(cp.CloseReason, 'N/A') as CloseReason,
        tc.CommenterId,
        tc.CommentDate,
        tc.ShortCommentText
    from UserPostDetails upd
    join PostTypes pt on upd.PostTypeId = pt.Id
    left join Posts p on p.OwnerUserId = upd.UserId and p.PostTypeId = upd.PostTypeId
    left join DuplicateLinks dl on p.Id = dl.PostId
    left join ClosedPosts cp on p.Id = cp.PostId
    left join TopComments tc on p.Id = tc.PostId
    where upd.PostCount > 1
)
select
    UserId,
    DisplayName,
    Location,
    PostType,
    PostCount,
    TotalScore,
    round(AvgScore,2) as AvgScore,
    TotalViews,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    NumDuplicates,
    LastClosedDate,
    CloseReason,
    CommenterId,
    CommentDate,
    ShortCommentText,
    case
        when GoldBadges > 10 then 'Elite'
        when SilverBadges > 20 then 'Experienced'
        when BronzeBadges > 50 then 'Frequent'
        else 'Newbie'
    end as UserBadgeLevel,
    concat('User ', coalesce(DisplayName, 'Unknown'), ' has ', PostType, ' posts: ', PostCount) as SummaryText
from FinalResult
order by TotalScore desc, PostCount desc, LastClosedDate nulls last
limit 100;