-- {"query": "2764.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1173} 
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
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
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
        avg(a.Score) filter (where a.Score is not null) as AvgAnswerScore
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
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
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
        sum(case when c.CreationDate > current_date - interval '30 day' then 1 else 0 end) as RecentComments
    from Comments c
    join Users u on u.Id = c.UserId
    group by c.UserId, u.DisplayName
),
TagUsage as (
    select 
        unnest(string_to_array(trim(both '<>' from t.Tags), '><')) as TagName,
        count(*) as UsageCount,
        count(distinct t.Id) as UniquePosts
    from Posts t
    where t.Tags is not null and t.PostTypeId = 1
    group by 1
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
    array_agg(distinct tu.TagName order by tu.UsageCount desc limit 3) filter (where tu.TagName is not null) as TopTags,
    wps.MovingAvgScore5,
    wps.ScoreRank,
    case 
        when ua.Reputation > 20000 and bs.GoldBadges >= 5 then 'Elite User'
        when ua.Reputation between 5000 and 20000 then 'Experienced User'
        else 'Newbie'
    end as UserCategory,
    case 
        when ua.Reputation = 0 then null
        else log(1 + ua.Reputation * greatest(1, ua.Reputation/1000)) end as ReputationLogScaled
from RecursiveUserActivity ua
left join BadgeSummary bs on bs.UserId = ua.UserId
left join PostAnswerStats pas on pas.OwnerUserId = ua.UserId
left join PostCloseReasons pcr on pcr.PostId = pas.QuestionId
left join UserCommentStats ucs on ucs.UserId = ua.UserId
left join TagUsage tu on tu.TagName = any(string_to_array(coalesce(ua.Tags, ''), '><'))
left join WindowedPostScores wps on wps.PostTypeId = ua.PostTypeId and wps.OwnerUserId = ua.UserId and wps.Id = ua.PostId
where ua.RecentPostRank <= 5
order by ua.Reputation desc, ua.UserId
limit 100;