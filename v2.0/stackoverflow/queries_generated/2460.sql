-- {"query": "2460.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1543} 
with RecursivePosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.Id as OwnerUserId,
        u.Reputation,
        u.DisplayName,
        row_number() over (partition by p.Id order by p.CreationDate desc) as rn
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2) and p.Tags is not null
    union all
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.Id,
        u.Reputation,
        u.DisplayName,
        1
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    inner join RecursivePosts rp on p.ParentId = rp.Id
    where p.PostTypeId = 2 and rp.rn = 1
),
TaggedQuestions as (
    select 
        Id,
        Tags,
        regexp_split_to_table(substring(Tags from 2 for length(Tags) - 2), '><') as Tag
    from Posts
    where PostTypeId = 1 and Tags is not null
),
TopTags as (
    select 
        Tag,
        count(*) as QuestionCount
    from TaggedQuestions
    group by Tag
    order by QuestionCount desc
    limit 10
),
UserBadgeCounts as (
    select 
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserBadgeSummary as (
    select 
        u.Id as UserId,
        coalesce(max(case when Class = 1 then BadgeCount end), 0) as GoldBadges,
        coalesce(max(case when Class = 2 then BadgeCount end), 0) as SilverBadges,
        coalesce(max(case when Class = 3 then BadgeCount end), 0) as BronzeBadges
    from Users u
    left join UserBadgeCounts ubc on u.Id = ubc.UserId
    group by u.Id
),
PostScoresWindow as (
    select 
        PostId,
        Score,
        sum(case when Score > 0 then Score else 0 end) over (partition by PostId order by PostId rows between unbounded preceding and current row) as CumulativePositiveScore,
        avg(Score) over (partition by PostId) as AvgScore,
        count(*) over () as TotalPosts
    from Posts
),
PostAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreated,
        count(a.Id) as AnswerCount,
        coalesce(avg(a.Score),0) as AvgAnswerScore,
        max(a.Score) as HighestAnswerScore,
        sum(case when a.Score > 5 then 1 else 0 end) as HighScoreAnswerCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate
),
PostCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    inner join CloseReasonTypes crt on ph.Comment::int = crt.Id
    where ph.PostHistoryTypeId = 10
),
QuestionsWithCloseInfo as (
    select 
        q.Id,
        q.Title,
        pcr.CloseReason,
        pcr.CloseDate
    from Posts q
    left join PostCloseReasons pcr on q.Id = pcr.PostId
    where q.PostTypeId = 1
),
DuplicateLinks as (
    select distinct
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id and lt.Name = 'Duplicate'
    inner join Posts p1 on pl.PostId = p1.Id
    inner join Posts p2 on pl.RelatedPostId = p2.Id
)
select 
    tp.Tag as TopTag,
    ps.QuestionId,
    ps.Title as QuestionTitle,
    ps.QuestionCreated,
    ps.AnswerCount,
    ps.AvgAnswerScore,
    ps.HighestAnswerScore,
    ps.HighScoreAnswerCount,
    u.DisplayName as QuestionOwner,
    u.Reputation as QuestionOwnerReputation,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    coalesce(qc.CloseReason, 'Open') as CloseStatus,
    qc.CloseDate,
    dl.DuplicateTitle,
    array_agg(distinct ph.Name) filter (where ph.PostHistoryTypeId in (4,5,6)) as RecentEditTypes,
    concat_ws(' | ', 
              'Score:', coalesce(to_char(p.Score, 'FM9999'), '0'),
              'Views:', coalesce(to_char(p.ViewCount, 'FM9999999'), '0'),
              'Favorites:', coalesce(to_char(p.FavoriteCount, 'FM9999'), '0')) as StatsSummary,
    case 
        when p.LastActivityDate is null then 'No recent activity'
        when p.LastActivityDate > now() - interval '30 days' then 'Active'
        else 'Inactive'
    end as ActivityStatus
from TopTags tp
inner join TaggedQuestions tq on tq.Tag = tp.Tag
inner join PostAnswerStats ps on ps.QuestionId = tq.Id
left join Users u on u.Id = (select OwnerUserId from Posts where Id = ps.QuestionId limit 1)
left join UserBadgeSummary ubs on ubs.UserId = u.Id
left join QuestionsWithCloseInfo qc on qc.Id = ps.QuestionId
left join Posts p on p.Id = ps.QuestionId
left join DuplicateLinks dl on dl.PostId = ps.QuestionId
left join LATERAL (
    select distinct ph2.PostHistoryTypeId, pht.Name 
    from PostHistory ph2
    inner join PostHistoryTypes pht on ph2.PostHistoryTypeId = pht.Id
    where ph2.PostId = ps.QuestionId
    order by ph2.CreationDate desc
    limit 5
) ph on true
where ps.AnswerCount > 3
and (u.Reputation > 1000 or u.Reputation is null)
group by tp.Tag, ps.QuestionId, ps.Title, ps.QuestionCreated, ps.AnswerCount, ps.AvgAnswerScore, ps.HighestAnswerScore, ps.HighScoreAnswerCount, u.DisplayName, u.Reputation, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, qc.CloseReason, qc.CloseDate, dl.DuplicateTitle, p.Score, p.ViewCount, p.FavoriteCount, p.LastActivityDate
order by ps.HighScoreAnswerCount desc, ps.AnswerCount desc, ps.AvgAnswerScore desc
limit 100;