-- {"query": "942.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1681} 
with RecursiveBadgeCounts as (
    select
        b.UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount,
        row_number() over (partition by b.UserId order by b.Class) as rn
    from Badges b
    join Users u on u.Id = b.UserId
    where b.TagBased = 0
    group by b.UserId, u.DisplayName, b.Class
),
UserBadgeSummary as (
    select
        rbc.UserId,
        rbc.DisplayName,
        sum(case when rbc.Class = 1 then rbc.BadgeCount else 0 end) as GoldBadges,
        sum(case when rbc.Class = 2 then rbc.BadgeCount else 0 end) as SilverBadges,
        sum(case when rbc.Class = 3 then rbc.BadgeCount else 0 end) as BronzeBadges
    from RecursiveBadgeCounts rbc
    group by rbc.UserId, rbc.DisplayName
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId = 1 and p.Score > 0
),
QuestionAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        avg(coalesce(a.Score,0)) as AvgAnswerScore,
        coalesce((
            select count(1) from Votes v2
            where v2.PostId = q.Id and v2.VoteTypeId = 5 -- Favorite
        ), 0) as FavoriteCount
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.OwnerUserId, q.Score, q.ViewCount
),
QuestionsWithCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int) and ph.PostHistoryTypeId = 10
    where ph.PostHistoryTypeId = 10
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as TotalQuestions,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as TotalAnswers,
        count(distinct c.Id) as TotalComments,
        coalesce(sum(vt.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vt.DownVotes),0) as TotalDownVotes,
        max(p.LastActivityDate) as LastActivity
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select
            PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) vt on vt.PostId = p.Id
    group by u.Id, u.DisplayName
),
QuestionTagExplode as (
    select
        p.Id as QuestionId,
        trim(both ' ' from unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'))) as TagName
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
TagPopularity as (
    select
        TagName,
        count(distinct QuestionId) as QuestionCount,
        avg(q.ViewCount) as AvgViewCount,
        avg(q.Score) as AvgScore
    from QuestionTagExplode qte
    join Posts q on q.Id = qte.QuestionId
    group by TagName
    having count(distinct QuestionId) > 100
),
TopAnswerersPerTag as (
    select distinct on (t.TagName, a.OwnerUserId)
        t.TagName,
        a.OwnerUserId,
        u.DisplayName,
        count(a.Id) over (partition by t.TagName, a.OwnerUserId) as AnswerCount,
        avg(a.Score) over (partition by t.TagName, a.OwnerUserId) as AvgAnswerScore,
        row_number() over (partition by t.TagName order by count(a.Id) desc, avg(a.Score) desc) as RankInTag
    from QuestionTagExplode t
    join Posts q on q.Id = t.QuestionId
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    join Users u on u.Id = a.OwnerUserId
    where a.OwnerUserId is not null
),
QualifiedTopAnswerers as (
    select
        TagName,
        OwnerUserId,
        DisplayName,
        AnswerCount,
        AvgAnswerScore
    from TopAnswerersPerTag
    where RankInTag <= 3
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    coalesce(ubs.GoldBadges, 0) as GoldBadges,
    coalesce(ubs.SilverBadges, 0) as SilverBadges,
    coalesce(ubs.BronzeBadges, 0) as BronzeBadges,
    ua.TotalPosts,
    ua.TotalQuestions,
    ua.TotalAnswers,
    ua.TotalComments,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ua.LastActivity,
    qs.QuestionId,
    qs.Title as QuestionTitle,
    qs.QuestionScore,
    qs.ViewCount as QuestionViews,
    qs.AnswerCount,
    qs.MaxAnswerScore,
    round(qs.AvgAnswerScore::numeric,2) as AvgAnswerScore,
    qs.FavoriteCount,
    cr.CloseReason,
    cr.CloseDate,
    qt.TagName as TopTag,
    qa.DisplayName as TopAnswererDisplayName,
    qa.AnswerCount as TopAnswererAnswerCount,
    round(qa.AvgAnswerScore::numeric,2) as TopAnswererAvgScore,
    case
        when u.WebsiteUrl is null or length(trim(u.WebsiteUrl)) = 0 then 'No Website'
        when u.WebsiteUrl like 'http%' then 'Valid URL'
        else 'Unknown Format'
    end as WebsiteStatus,
    coalesce(nullif(substring(u.Location from '^[^,]+'), ''), 'Unknown') as PrimaryLocation
from Users u
left join UserBadgeSummary ubs on ubs.UserId = u.Id
left join UserActivitySummary ua on ua.Id = u.Id
left join (
    select *
    from QuestionAnswerStats
    where AnswerCount > 0
) qs on qs.OwnerUserId = u.Id
left join QuestionsWithCloseReasons cr on cr.PostId = qs.QuestionId
left join lateral (
    select TagName
    from QuestionTagExplode
    where QuestionId = qs.QuestionId
    order by TagName
    limit 1
) qt on true
left join QualifiedTopAnswerers qa on qa.TagName = qt.TagName
where u.Reputation > 1000 and ua.TotalPosts > 50
order by u.Reputation desc, ua.TotalPosts desc
limit 100;