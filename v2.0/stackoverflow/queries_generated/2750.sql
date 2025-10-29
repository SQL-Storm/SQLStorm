-- {"query": "2750.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1166} 
with RecursiveTopTags as (
    select
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id as OwnerUserId,
        u.DisplayName,
        dense_rank() over (order by t.Count desc) as TagRank
    from Tags t
    join Posts p on p.PostTypeId = 1 and ('<' || t.TagName || '>') = any(string_to_array(trailing('>' from substring(p.Tags, 2, length(p.Tags)-2)), '><'))
    left join Users u on u.Id = p.OwnerUserId
    where t.Count > 5000
    union all
    select
        r.TagName,
        r.Count,
        pl.PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.Id,
        u.DisplayName,
        r.TagRank
    from RecursiveTopTags r
    join PostLinks pl on pl.RelatedPostId = r.PostId and pl.LinkTypeId = 3  -- duplicates
    join Posts p on p.Id = pl.PostId
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1 and p.CreationDate > r.CreationDate - interval '30 day' and r.TagRank <= 5
),
RankedAnswers as (
    select
        a.Id,
        a.ParentId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2 and a.Score is not null
),
UserBadgesStats as (
    select
        b.UserId,
        count(*) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
UserActivityWindowed as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
        max(p.Score) filter (where p.PostTypeId in (1,2)) as MaxPostScore,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc NULLS LAST) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Location, u.Views, u.UpVotes, u.DownVotes
)
select
    rt.TagRank,
    rt.TagName,
    rt.Count as TagCount,
    rt.PostId as QuestionId,
    rt.Score as QuestionScore,
    rt.ViewCount as QuestionViews,
    rt.CreationDate as QuestionCreationDate,
    coalesce(rt.DisplayName, 'anonymous') as QuestionOwner,
    ra.Id as TopAnswerId,
    ra.Score as TopAnswerScore,
    ra.CreationDate as TopAnswerCreationDate,
    coalesce(ra.DisplayName, 'anonymous') as TopAnswerOwner,
    uas.UserRank,
    uas.Reputation as AnswerOwnerReputation,
    ubs.TotalBadges,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    case
        when ra.Score >= 10 then 'Highly Upvoted'
        when ra.Score between 5 and 9 then 'Moderately Upvoted'
        when ra.Score < 5 and ra.Score > 0 then 'Low Upvoted'
        else 'Not Upvoted'
    end as AnswerPopularity,
    case
        when rt.ViewCount > 10000 then 'Very Popular'
        when rt.ViewCount between 1000 and 9999 then 'Popular'
        else 'Normal'
    end as QuestionPopularityCategory,
    concat(
        coalesce(uas.Location, 'Unknown'), ' / ',
        coalesce(uas.Views::text, '0'), ' views / ',
        coalesce(uas.UpVotes::text, '0'), ' upvotes / ',
        coalesce(uas.DownVotes::text, '0'), ' downvotes'
    ) as AnswerOwnerStatsSnippet
from RecursiveTopTags rt
left join RankedAnswers ra on ra.ParentId = rt.PostId and ra.AnswerRank = 1
left join UserActivityWindowed uas on uas.Id = ra.OwnerUserId
left join UserBadgesStats ubs on ubs.UserId = ra.OwnerUserId
where rt.TagRank <= 5
order by rt.TagRank, QuestionScore desc, TopAnswerScore desc
limit 100;