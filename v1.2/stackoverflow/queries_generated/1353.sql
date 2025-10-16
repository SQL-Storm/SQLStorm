-- {"query": "1353.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1613} 
with RecursiveUserBadges as (
    select 
        u.Id as UserId, 
        u.DisplayName, 
        u.Reputation,
        b.Name as BadgeName,
        b.Class as BadgeClass,
        b.Date as BadgeDate,
        row_number() over (partition by u.Id order by b.Date desc, b.Class, b.Name) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId and b.Date < '2023-01-01'
    where u.Reputation > (select avg(Reputation) from Users)
),
RecentPostsWithLinks as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title, 
        p.Tags,
        pt.Name as PostTypeName,
        pl.Id as LinkId,
        lt.Name as LinkTypeName,
        pl.RelatedPostId,
        rp.Score as RelatedPostScore,
        coalesce(NULLIF(p.Tags, ''), '<untagged>') as TagList,
        (select count(*) 
         from Comments c
         where c.PostId = p.Id and c.CreationDate >= p.CreationDate - interval '30 day'
        ) as RecentCommentCount
    from Posts p
    left join PostTypes pt on p.PostTypeId = pt.Id
    left join PostLinks pl on p.Id = pl.PostId and pl.CreationDate > p.CreationDate - interval '180 day'
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    left join Posts rp on pl.RelatedPostId = rp.Id
    where p.CreationDate >= current_date - interval '1 year'
),
AggregatedUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) as TotalPosts,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsPosted,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        sum(vCount.UpVotes) as TotalUpVotes,
        sum(vCount.DownVotes) as TotalDownVotes,
        max(p.Score) filter (where p.Score is not null) as MaxPostScore,
        min(u.CreationDate) as UserCreated,
        max(p.LastActivityDate) as LastActive,
        count(distinct ph.Id) filter (where ph.PostHistoryTypeId in (10, 11)) as CloseReopenEvents,
        count(distinct knockout.DuplicateLinks) filter (where knockout.DuplicateLinks is not null) as DuplicateLinkCount
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select 
            p.OwnerUserId, 
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vCount on vCount.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join (
        select 
            pl.PostId, 
            count(pl.Id) as DuplicateLinks
        from PostLinks pl
        where pl.LinkTypeId = 3
        group by pl.PostId
    ) knockout on knockout.PostId = p.Id
    group by u.Id, u.DisplayName
),
UserRankings as (
    select *,
        rank() over (order by TotalPosts desc, Reputation desc) as RankByPosts,
        dense_rank() over (order by TotalUpVotes desc nulls last) as RankByUpVotes,
        ntile(10) over (order by Reputation) as ReputationDecile
    from AggregatedUserActivity
),
CorrelatedAnswerScores as (
    select
        a.Id,
        a.OwnerUserId,
        a.Score,
        q.Score as QuestionScore,
        q.Id as QuestionId,
        (select count(*) 
         from Posts a2 
         where a2.ParentId = q.Id and a2.Score > a.Score
        ) as AnswersWithHigherScore,
        (select coalesce(max(Score), 0)
         from Posts a3
         where a3.ParentId = q.Id
        ) as MaxScoreForAnswers
    from Posts a
    join Posts q on a.ParentId = q.Id and q.PostTypeId = 1
    where a.PostTypeId = 2
),
TopAnswerersAndTheirBadges as (
    select 
        u.Id as UserId,
        u.DisplayName as UserDisplayName,
        count(distinct a.Id) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Score > b.MaxScoreForAnswers * 0.8 then 1 else 0 end) as HighScoringAnswers,
        string_agg(distinct c.Name || ' (' || c.Class || ')', ', ') as BadgeSummary
    from Posts a
    join Users u on a.OwnerUserId = u.Id
    join CorrelatedAnswerScores b on a.Id = b.Id
    left join Badges c on c.UserId = u.Id
    where a.PostTypeId = 2 and a.Score > 10
    group by u.Id, u.DisplayName
    having count(distinct a.Id) > 5
)
select 
    u.UserId,
    u.DisplayName,
    u.TotalPosts,
    u.QuestionsPosted,
    u.AnswersPosted,
    u.CommentsMade,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.MaxPostScore,
    u.LastActive,
    r.RankByPosts,
    r.RankByUpVotes,
    r.ReputationDecile,
    case 
        when b.HighScoringAnswers is not null then b.HighScoringAnswers 
        else 0 
    end as HighScoringAnswers,
    coalesce(b.BadgeSummary, 'No badges') as BadgeSummary,
    arr.TagsAsText
from UserRankings r
join AggregatedUserActivity u on u.UserId = r.UserId
left join TopAnswerersAndTheirBadges b on b.UserId = u.UserId
left join lateral (
    select string_agg(distinct unnest(string_to_array(replace(replace(p.Tags, '<', ''), '>', ''), ' ')), ', ') as TagsAsText
    from Posts p
    where p.OwnerUserId = u.UserId and p.Tags is not null
) arr on true
where r.RankByPosts <= 100
-- unions breaking and complex NULL logic
union
select 
    u.UserId,
    u.DisplayName,
    u.TotalPosts,
    u.QuestionsPosted,
    u.AnswersPosted,
    u.CommentsMade,
    u.TotalUpVotes,
    u.TotalDownVotes,
    u.MaxPostScore,
    u.LastActive,
    r.RankByPosts,
    r.RankByUpVotes,
    r.ReputationDecile,
    0,
    'No badges - from union dummy',
    null
from UserRankings r
join AggregatedUserActivity u on u.UserId = r.UserId
where u.TotalPosts = 0
order by TotalPosts desc nulls last, TotalUpVotes desc nulls last, DisplayName
limit 50;