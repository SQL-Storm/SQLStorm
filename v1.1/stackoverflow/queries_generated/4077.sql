-- {"query": "4077.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1707} 
with RecursiveTagCounts as (
    select
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as Tag,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
), 
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionsCount,
        count(distinct p.Id) filter (where p.PostTypeId=2) as AnswersCount,
        count(distinct b.Id) as BadgesCount,
        coalesce(sum(v.UpVotes),0) as TotalUpVotes,
        coalesce(sum(v.DownVotes),0) as TotalDownVotes,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join (
        select OwnerUserId,
               sum(COALESCE(UpVotes,0)) as UpVotes,
               sum(COALESCE(DownVotes,0)) as DownVotes
        from Users
        group by OwnerUserId
    ) v on v.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), PostCloseDetails as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId,
        max(ph.CreationDate) as CloseDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
), TopUserTags as (
    select
        utc.OwningUserId,
        utc.Tag,
        sum(utc.Score) as TotalScore,
        count(*) as TagPostCount,
        dense_rank() over (partition by utc.OwningUserId order by sum(utc.Score) desc) as TagRank
    from (
        select
            p.OwnerUserId as OwningUserId,
            unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag,
            p.Score
        from Posts p
        where p.PostTypeId = 1 and p.Tags is not null
    ) utc
    group by utc.OwningUserId, utc.Tag
), AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(p.Id) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
), DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId limit 1)
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3
), UserBadgeSummary as (
    select
        b.UserId,
        b.Name,
        count(*) as BadgeCount,
        max(b.Date) as LastAwarded
    from Badges b
    group by b.UserId, b.Name
), RankedPosts as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as RankByScoreView
    from Posts p
    where p.PostTypeId in (1,2)
)
select
    u.DisplayName as User,
    u.Reputation,
    ua.QuestionsCount,
    ua.AnswersCount,
    ua.BadgesCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    coalesce(ps.AnswerCount,0) as TotalAnswersForUserQuestions,
    coalesce(ps.AvgAnswerScore,0) as AvgAnswerScoreForUserQuestions,
    coalesce(ps.MaxAnswerScore,0) as MaxAnswerScoreForUserQuestions,
    coalesce(ps.MinAnswerScore,0) as MinAnswerScoreForUserQuestions,
    coalesce(tc.Tags, '') as TopTagsCSV,
    coalesce(dup.DuplicateCount,0) as DuplicateCount,
    coalesce(cb.BadgeList, '') as BadgesCSV,
    bestPosts.BestQuestionTitle,
    bestPosts.BestAnswerScore,
    (select count(*) from Comments c where c.UserId = u.Id and c.CreationDate > u.CreationDate) as UserCommentCount,
    -- Complex conditional expression with null handling and string functions:
    case 
        when u.WebsiteUrl is null or length(trim(u.WebsiteUrl)) = 0 then 'No website'
        else 'Website: ' || substring(u.WebsiteUrl from 1 for 30) || case when length(u.WebsiteUrl) > 30 then '...' else '' end
    end as WebsiteShort,
    -- Window function usage with NULL logic:
    sum(voteCounts.UpModCount) over (order by u.Reputation desc rows between unbounded preceding and current row) as CumulativeUpVotes,
    rank() over (order by ua.QuestionsCount desc) as RankByQuestionsCount
from Users u
left join UserActivity ua on ua.UserId = u.Id
left join (
    select
        p.OwnerUserId,
        count(p.Id) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.OwnerUserId
) ps on ps.OwnerUserId = u.Id
left join (
    select
        OwningUserId,
        string_agg(Tag, ', ') as Tags
    from TopUserTags
    where TagRank <= 5
    group by OwningUserId
) tc on tc.OwningUserId = u.Id
left join (
    select
        pl.PostId as PostOwnerUserId,
        count(*) as DuplicateCount
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    where pl.LinkTypeId = 3
    group by pl.PostId
) dup on dup.PostOwnerUserId = u.Id
left join (
    select
        b.UserId,
        string_agg(b.Name || '(' || b.Class || ')', ', ') as BadgeList
    from Badges b
    group by b.UserId
) cb on cb.UserId = u.Id
left join (
    select distinct on (p.OwnerUserId)
        p.OwnerUserId,
        p.Title as BestQuestionTitle,
        p.Score as BestAnswerScore
    from Posts p
    where p.PostTypeId = 1
    order by p.OwnerUserId, p.Score desc, p.ViewCount desc
) bestPosts on bestPosts.OwnerUserId = u.Id
left join (
    select
        v.UserId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpModCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
) voteCounts on voteCounts.UserId = u.Id
where ua.QuestionsCount > 5
order by ua.QuestionsCount desc, ua.AnswersCount desc
limit 50;