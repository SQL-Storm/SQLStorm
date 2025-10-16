-- {"query": "1047.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1568} 
with RecursiveClosedQuestions as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.OwnerUserId,
        p.AcceptedAnswerId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        coalesce(p.LastActivityDate, p.CreationDate) as LastActivity,
        -- Detect if closed more than once by historical posthistory of type 'Post Closed' (Id=10)
        (select count(*) from PostHistory ph where ph.PostId = p.Id and ph.PostHistoryTypeId = 10) as ClosedCount,
        row_number() over (partition by p.OwnerUserId order by coalesce(p.LastActivityDate, p.CreationDate) desc) as UserRecentRank
    from
        Posts p
    where
        p.PostTypeId = 1 -- questions only
        and p.ClosedDate is not null
),
RecentBadgedUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from
        Users u
        left join Badges b on b.UserId = u.Id
    group by
        u.Id, u.DisplayName, u.Reputation
    having
        count(b.Id) > 0
),
UserAnswerStats as (
    select
        a.OwnerUserId as UserId,
        count(a.Id) as TotalAnswers,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.ParentId is not null then 1 else 0 end) as ValidParentAnswers,
        max(a.CreationDate) as LastAnswerDate
    from
        Posts a
    where
        a.PostTypeId = 2 -- answers only
    group by
        a.OwnerUserId
),
CTE_VotedQuestions AS (
    select
        v.PostId,
        count(*) as TotalVotes,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from
        Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
    group by
        v.PostId
),
TaggedClosedQ as (
    select
        rcq.*,
        ctv.TotalVotes,
        ctv.UpVotes,
        ctv.DownVotes,
        ctv.Favorites,
        -- Extract the first tag for demonstration (tags are stored like '<tag1><tag2><tag3>')
        split_part(split_part(rcq.Tags, '><', 1), '<', 2) as FirstTag
    from
        RecursiveClosedQuestions rcq
        left join CTE_VotedQuestions ctv on ctv.PostId = rcq.Id
),
UserDistribution AS (
    select 
        u.Id,
        u.DisplayName,
        u.Location,
        u.Views,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        row_number() over (partition by coalesce(u.Location, 'Unknown') order by u.Reputation desc) as LocationRank,
        case 
            when u.Reputation >= 10000 then 'Expert'
            when u.Reputation >= 1000 then 'Intermediate'
            else 'Beginner'
        end as UserLevel
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
    group by
        u.Id, u.DisplayName, u.Location, u.Views, u.Reputation
),
BestAnswerWithContext AS (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.CreationDate as AnswerCreated,
        a.Score as AnswerScore,
        q.Title as QuestionTitle,
        q.Tags as QuestionTags,
        u.DisplayName as AnswerOwnerName,
        rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from
        Posts a
        join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
        left join Users u on u.Id = a.OwnerUserId
    where
        a.PostTypeId = 2
)
select
    tcq.Id as ClosedQuestionId,
    tcq.Title,
    tcq.CreationDate,
    tcq.OwnerUserId,
    rb.UserLevel,
    rb.DisplayName as OwnerDisplayName,
    tcq.Score,
    tcq.ViewCount,
    tcq.AnswerCount,
    tcq.FavoriteCount,
    coalesce(tcq.TotalVotes, 0) as TotalVotes,
    coalesce(tcq.UpVotes, 0) as UpVotes,
    coalesce(tcq.DownVotes, 0) as DownVotes,
    coalesce(tcq.Favorites, 0) as TotalFavorites,
    tcq.ClosedDate,
    tcq.ClosedCount,
    tcq.LastActivity,
    bsu.GoldBadges,
    bsu.SilverBadges,
    bsu.BronzeBadges,
    uas.TotalAnswers,
    uas.AvgAnswerScore,
    uas.ValidParentAnswers,
    uas.LastAnswerDate,
    ud.Location,
    ud.UserLevel as UserReputationLevel,
    ba.AnswerId as HighestScoreAnswerId,
    ba.AnswerScore as HighestAnswerScore,
    ba.AnswerCreated as HighestAnswerCreationDate,
    ba.AnswerOwnerName as HighestAnswerOwner,
    ba.QuestionTitle as HighestAnswerQuestionTitle,
    ba.QuestionTags as HighestAnswerQuestionTags
from
    TaggedClosedQ tcq
    left join RecentBadgedUsers bsu on bsu.UserId = tcq.OwnerUserId
    left join UserAnswerStats uas on uas.UserId = tcq.OwnerUserId
    left join UserDistribution ud on ud.Id = tcq.OwnerUserId
    left join BestAnswerWithContext ba on ba.QuestionId = tcq.Id and ba.AnswerRank = 1
    left join (select Id, UserLevel, DisplayName from UserDistribution) rb on rb.Id = tcq.OwnerUserId
where
    -- Complex predicate demonstrating string length, numeric expressions and null logic
    length(coalesce(tcq.Title, '')) > 30
    and (tcq.Score * 1.2 + coalesce(tcq.AnswerCount,0) * 3) > 10
    and (tcq.ClosedCount > 1 or tcq.FavoriteCount > 0)
    and coalesce(bsu.GoldBadges, 0) + coalesce(bsu.SilverBadges, 0) + coalesce(bsu.BronzeBadges, 0) >= 5
order by
    tcq.LastActivity desc,
    tcq.Score desc
limit 100;