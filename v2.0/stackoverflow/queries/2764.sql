with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        coalesce(p.Title, '') as Title,
        p.Tags,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
BadgeSummary as (
    select 
        b.UserId,
        count(case when b.Class = 1 then 1 end) as GoldBadges,
        count(case when b.Class = 2 then 1 end) as SilverBadges,
        count(case when b.Class = 3 then 1 end) as BronzeBadges,
        count(distinct b.Name) as DistinctBadgeCount
    from Badges b
    group by b.UserId
),
PostAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        count(distinct a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        sum(case when a.Score >= 10 then 1 else 0 end) as HighScoreAnswerCount,
        avg(a.Score) as AvgAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId
),
PostCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        max(ph.CreationDate) as LastClosed
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer)
    where ph.PostHistoryTypeId = 10 and ph.Comment is not null and ph.Comment ~ '^\d+$'
    group by ph.PostId, crt.Name
),
UserCommentStats as (
    select 
        c.UserId,
        u.DisplayName,
        count(c.Id) as TotalComments,
        count(distinct c.PostId) as PostsCommentedOn,
        avg(length(c.Text)) as AvgCommentLength,
        sum(case when c.CreationDate > (cast('2024-10-01' as date) - interval '30' day) then 1 else 0 end) as RecentComments
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
TagUsage as (
    select 
        tag as TagName,
        count(*) as UsageCount,
        count(distinct t.Id) as UniquePosts
    from Posts t
    cross join lateral (
      select trim(both '<>' from t.Tags) as rawtags
    ) rt
    cross join lateral (
      select unnest(string_to_array(rt.rawtags, '><')) as tag
    ) tu
    where t.Tags is not null and t.PostTypeId = 1
    group by tag
),
WindowedPostScores as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        avg(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between 4 preceding and current row) as MovingAvgScore5,
        rank() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
)
select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.DistinctBadgeCount,
    pas.AnswerCount,
    pas.MaxAnswerScore,
    pas.HighScoreAnswerCount,
    pas.AvgAnswerScore,
    coalesce(pcr.CloseReason, 'Not Closed') as LastCloseReason,
    ucs.TotalComments,
    ucs.PostsCommentedOn,
    ucs.AvgCommentLength,
    ucs.RecentComments,
    (select array_agg(tn) from (
        select tu2.TagName as tn
        from TagUsage tu2
        where tu2.TagName is not null and tu2.TagName = any(string_to_array(coalesce(ua.Tags, ''), '><'))
        order by tu2.UsageCount desc
        limit 3
    ) s) as TopTags,
    wps.MovingAvgScore5,
    wps.ScoreRank,
    case 
        when ua.Reputation > 20000 and coalesce(bs.GoldBadges,0) >= 5 then 'Elite User'
        when ua.Reputation between 5000 and 20000 then 'Experienced User'
        else 'Newbie'
    end as UserCategory,
    case 
        when ua.Reputation = 0 then null
        else ln(1 + ua.Reputation * greatest(1, ua.Reputation/1000.0)) end as ReputationLogScaled
from RecursiveUserActivity ua
left join BadgeSummary bs on bs.UserId = ua.UserId
left join PostAnswerStats pas on pas.OwnerUserId = ua.UserId
left join PostCloseReasons pcr on pcr.PostId = pas.QuestionId
left join UserCommentStats ucs on ucs.UserId = ua.UserId
left join WindowedPostScores wps on wps.PostTypeId = ua.PostTypeId and wps.OwnerUserId = ua.UserId and wps.Id = ua.PostId
where ua.RecentPostRank <= 5
group by
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    bs.GoldBadges,
    bs.SilverBadges,
    bs.BronzeBadges,
    bs.DistinctBadgeCount,
    pas.AnswerCount,
    pas.MaxAnswerScore,
    pas.HighScoreAnswerCount,
    pas.AvgAnswerScore,
    pcr.CloseReason,
    ucs.TotalComments,
    ucs.PostsCommentedOn,
    ucs.AvgCommentLength,
    ucs.RecentComments,
    wps.MovingAvgScore5,
    wps.ScoreRank,
    ua.PostId,
    ua.PostTypeId,
    ua.Tags
order by ua.Reputation desc, ua.UserId
limit 100;