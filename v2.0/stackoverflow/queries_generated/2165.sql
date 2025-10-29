-- {"query": "2165.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1218} 
with RecursiveUserBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Id as BadgeId,
        b.Name as BadgeName,
        b.Class,
        b.TagBased,
        b.Date,
        row_number() over(partition by u.Id order by b.Date desc, b.Class) as BadgeRank
    from Users u
    left join Badges b on b.UserId = u.Id
    where u.Reputation > 1000
),
UserTopBadges as (
    select * 
    from RecursiveUserBadges
    where BadgeRank <= 3
),
PostAnswerStats as (
    select
        p.Id as QuestionId,
        p.Title,
        p.OwnerUserId,
        count(a.Id) as AnswerCount,
        max(a.Score) as MaxAnswerScore,
        coalesce(avg(nullif(a.Score,0)), 0) as AvgNonZeroAnswerScore,
        sum(case when a.Score > 5 then 1 else 0 end) as HighScoreAnswerCount,
        max(a.CreationDate) as LastAnswerDate
    from Posts p
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where p.PostTypeId = 1 and p.CreationDate >= current_date - interval '180 days'
    group by p.Id, p.Title, p.OwnerUserId
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate
    from PostHistory ph
    inner join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        row_number() over(partition by u.Id order by v.CreationDate desc) as RecentVoteRank
    from Users u
    left join Votes v on v.UserId = u.Id
    where u.Reputation > 5000
),
UserRecentVotes as (
    select
        UserId,
        VoteTypeId,
        count(*) as VoteCount
    from UserActivityWindow
    where RecentVoteRank <= 20
    group by UserId, VoteTypeId
),
UserTopTags as (
    select
        u.Id as UserId,
        t.TagName,
        count(*) as TagCount
    from Users u
    join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    cross join lateral unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags)-2), '><')) as t(TagName)
    group by u.Id, t.TagName
    having count(*) > 10
),
QuestionWithTopAnswers as (
    select
        pas.QuestionId,
        pas.Title,
        pas.OwnerUserId,
        pas.AnswerCount,
        pas.MaxAnswerScore,
        pas.AvgNonZeroAnswerScore,
        pas.HighScoreAnswerCount,
        pas.LastAnswerDate,
        p.TimestampRank,
        p.ScoreRank
    from PostAnswerStats pas
    left join (
        select
            Id,
            rank() over(order by CreationDate desc) as TimestampRank,
            rank() over(order by Score desc) as ScoreRank
        from Posts
        where PostTypeId = 1
    ) p on p.Id = pas.QuestionId
)
select
    q.QuestionId,
    left(q.Title, 100) || case when char_length(q.Title) > 100 then '...' else '' end as ShortTitle,
    u.DisplayName as QuestionOwner,
    q.AnswerCount,
    q.MaxAnswerScore,
    round(q.AvgNonZeroAnswerScore, 2) as AvgAnswerScore,
    q.HighScoreAnswerCount,
    q.LastAnswerDate,
    cr.CloseReasonName,
    coalesce(badges.BadgeSummary, 'No top badges') as BadgeSummary,
    coalesce(votes.FavoriteVotes, 0) as FavoriteVotesLast20,
    coalesce(tags.TopTag, 'N/A') as TopTag,
    case when q.ScoreRank <= 100 then 'Top 100 Score' else 'Below Top 100' end as ScoreCategory,
    case when q.TimestampRank <= 100 then 'Top 100 Newest' else 'Older' end as RecencyCategory
from QuestionWithTopAnswers q
inner join Users u on u.Id = q.OwnerUserId
left join PostCloseReasons cr on cr.PostId = q.QuestionId
left join (
    select
        UserId,
        string_agg(distinct Class || ':' || BadgeName, '; ') filter (where BadgeRank <= 3) as BadgeSummary
    from RecursiveUserBadges
    group by UserId
) badges on badges.UserId = u.Id
left join (
    select
        UserId,
        sum(case when VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes
    from UserRecentVotes
    group by UserId
) votes on votes.UserId = u.Id
left join (
    select
        ut.UserId,
        ut.TagName as TopTag
    from (
        select
            UserId,
            TagName,
            row_number() over(partition by UserId order by TagCount desc) as TagRank
        from UserTopTags
    ) ut
    where ut.TagRank = 1
) tags on tags.UserId = u.Id
where q.AnswerCount > 0
order by q.HighScoreAnswerCount desc nulls last, q.MaxAnswerScore desc nulls last, q.LastAnswerDate desc nulls last
limit 50;