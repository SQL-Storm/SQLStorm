-- {"query": "1530.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1539} 
with TagUsage as (
    select
        p.Id as PostId,
        u.Id as UserId,
        u.DisplayName,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    inner join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId = 1 -- questions only
),
UserBadgeCount as (
    select
        b.UserId,
        count(*) as BadgeCount,
        max(b.Class) as MaxBadgeClass
    from Badges b
    group by b.UserId
),
QuestionScores as (
    select
        p.Id,
        p.ViewCount,
        p.Score,
        p.FavoriteCount,
        case when p.AcceptedAnswerId is null then 0 else 1 end as HasAcceptedAnswer
    from Posts p
    where p.PostTypeId = 1
),
AnswerScores as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        sum(p.Score) as TotalAnswerScore,
        max(p.Score) as MaxAnswerScore,
        sum(case when exists(
            select 1 from Votes v 
            where v.PostId = p.Id and v.VoteTypeId = 10 -- Deletion votes for answer
        ) then 1 else 0 end) as AnswerDeletionVotes
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
ReputationSummaries as (
    select
        u.Id,
        u.Reputation,
        u.UpVotes,
        u.DownVotes,
        count(distinct coalesce(p.Id,0)) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct coalesce(p.Id,0)) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct b.Id) as BadgesEarned
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes
),
CloseVotesQueries as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesCount,
        bool_or(ph.PostHistoryTypeId = 11) as IsReopened
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)
    group by ph.PostId
),
PostsWithClosestBadges AS (
    select
        p.Id,
        p.Title,
        rbs.BadgeCount,
        rbs.MaxBadgeClass,
        csq.CloseVotesCount,
        csq.IsReopened,
        array_agg(distinct tb.Tag order by tb.Tag) as TagsPresented
    from Posts p
    left join UserBadgeCount rbs on p.OwnerUserId = rbs.UserId
    left join CloseVotesQueries csq on csq.PostId = p.Id
    left join TagUsage tb on p.Id = tb.PostId
    where p.PostTypeId = 1
    group by p.Id, p.Title, rbs.BadgeCount, rbs.MaxBadgeClass, csq.CloseVotesCount, csq.IsReopened
),
AugmentedPosts as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.FavoriteCount,
        p.HasAcceptedAnswer,
        ans.TotalAnswerScore,
        ans.AnswerCount,
        ans.MaxAnswerScore,
        ans.AnswerDeletionVotes,
        rbc.BadgeCount,
        rbc.MaxBadgeClass,
        tag.TagsPresented,
        close.CloseVotesCount,
        close.IsReopened,
        rank() OVER (PARTITION BY tagbt.Tag ORDER BY p.Score desc, p.FavoriteCount desc NULLS LAST, p.ViewCount desc NULLS LAST)
            as ScoreRankWithinTag
    from QuestionScores p
    left join AnswerScores ans on ans.QuestionId = p.Id
    left join PostsWithClosestBadges rbc on rbc.Id = p.Id
    left join TagUsage tagp on tagp.PostId = p.Id -- for correlation subquery below
    left join LATERAL (
        select array_agg(distinct tag order by tag) as TagUuid from TagUsage tag where tag.PostId = p.Id
    ) tagnt(Tag) on true
    left join CloseVotesQueries close on close.PostId = p.Id
    left join TagUsage tagbt on tagbt.PostId = p.Id
),
HighRankScoreTags AS (
    select distinct Tag
    from AugmentedPosts
    where ScoreRankWithinTag <= 3
),
FilteredHighScorePosts AS (
    select distinct Id, Title, Score, BadgeCount, MaxBadgeClass, CloseVotesCount, IsReopened, TagsPresented, AnswerCount, TotalAnswerScore
    from AugmentedPosts a
    where exists (
      select 1
      from unnest(a.TagsPresented) t(tag)
      where tag in (select Tag from HighRankScoreTags)
    ) and Score > 50 and (CloseVotesCount is null or CloseVotesCount = 0)
)
select
    p.Id,
    p.Title,
    p.Score,
    p.AnswerCount,
    p.TotalAnswerScore,
    p.BadgeCount,
    p.MaxBadgeClass,
    coalesce(p.CloseVotesCount,0) as CloseVotesCount,
    p.IsReopened,
    string_agg(distinct t.TagName, ',' order by t.TagName) as TagNames,
    (
        select count(*) 
        from Votes v2 
        where v2.PostId = p.Id and v2.VoteTypeId = 2
          and v2.CreationDate > p.VersionedCreationDate
    ) as RecentUpVotesCount
from FilteredHighScorePosts p
left join Tags t on t.TagName = any(p.TagsPresented) 
left join LATERAL (select min(CreationDate) as VersionedCreationDate from Posts where Id = p.Id) ver on true
group by 
    p.Id, p.Title, p.Score, p.BadgeCount, p.MaxBadgeClass, p.CloseVotesCount, p.IsReopened, p.AnswerCount, p.TotalAnswerScore, ver.VersionedCreationDate
union
select
    p.Id,
    p.Title,
    -p.Score as Score,
    p.AnswerCount,
    p.TotalAnswerScore,
    p.BadgeCount,
    p.MaxBadgeClass,
    coalesce(p.CloseVotesCount,0) as CloseVotesCount,
    p.IsReopened,
    string_agg(distinct t.TagName, ',' order by t.TagName) as TagNames,
    0 as RecentUpVotesCount
from FilteredHighScorePosts p
left join Tags t on t.TagName = any(p.TagsPresented)
left join LATERAL (select min(CreationDate) as VersionedCreationDate from Posts where Id = p.Id) ver on true
group by 
    p.Id, p.Title, p.Score, p.BadgeCount, p.MaxBadgeClass, p.CloseVotesCount, p.IsReopened, p.AnswerCount, p.TotalAnswerScore, ver.VersionedCreationDate
order by Score desc
limit 100;