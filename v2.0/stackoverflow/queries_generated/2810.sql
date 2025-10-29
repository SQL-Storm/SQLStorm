-- {"query": "2810.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1250} 
with RecursiveCTE as (
    select p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
           regexp_split_to_table(trim(both '<>' from coalesce(p.Tags, '')), '><') as Tag,
           1 as Depth
    from Posts p
    where p.PostTypeId = 1
    union all
    select pl.RelatedPostId as Id, p2.PostTypeId, p2.OwnerUserId, p2.CreationDate, p2.Score, p2.ViewCount, p2.Tags,
           regexp_split_to_table(trim(both '<>' from coalesce(p2.Tags, '')), '><') as Tag,
           r.Depth + 1
    from RecursiveCTE r
    join PostLinks pl on pl.PostId = r.Id and pl.LinkTypeId = 1
    join Posts p2 on p2.Id = pl.RelatedPostId
    where r.Depth < 3
),
UserActivity as (
    select u.Id as UserId, u.DisplayName, u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId=1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId=2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        count(distinct b.Id) as BadgesCount,
        max(vp.Score) as MaxPostScore,
        avg(vp.Score) filter (where vp.Score > 0) as AvgPositivePostScore,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesReceived,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesReceived,
        sum(case when v.VoteTypeId = 8 then v.BountyAmount else 0 end) as TotalBountyStarted
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Posts vp on vp.Id = v.PostId
    group by u.Id, u.DisplayName, u.Reputation
),
RankedPosts as (
    select 
        p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as RankByScoreView,
        count(*) over (partition by p.OwnerUserId) as PostCountByUser,
        dense_rank() over (order by p.Score desc nulls last) as GlobalScoreRank
    from Posts p
    where p.PostTypeId in (1,2)
),
TopTags as (
    select Tag, count(*) as TagUsageCount
    from RecursiveCTE
    where Tag is not null and length(Tag) > 0
    group by Tag
    having count(*) > 50
),
FilteredQuestions as (
    select p.Id, p.Title, p.CreationDate, p.Score, p.ViewCount, p.Tags, p.OwnerUserId,
        (select count(*) from Comments c where c.PostId = p.Id) as CommentCount,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes
    from Posts p
    where p.PostTypeId = 1
    and p.Score > 10
    and coalesce(p.ViewCount, 0) > 1000
    and exists (
        select 1 from TopTags tt where tt.Tag = any(string_to_array(trim(both '<>' from p.Tags), '><'))
    )
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionsAsked,
    u.AnswersGiven,
    u.CommentsMade,
    u.BadgesCount,
    u.MaxPostScore,
    u.AvgPositivePostScore,
    u.UpVotesReceived,
    u.DownVotesReceived,
    u.TotalBountyStarted,
    p.Id as PostId,
    p.Title as PostTitle,
    p.CreationDate as PostCreated,
    p.Score as PostScore,
    p.ViewCount as PostViews,
    p.Tags as PostTags,
    p.RankByScoreView,
    p.PostCountByUser,
    p.GlobalScoreRank,
    fq.CommentCount,
    fq.UpVotes,
    fq.DownVotes,
    coalesce(nullif(p.RankByScoreView, 0), 9999) * coalesce(p.Score, 0) / nullif(u.Reputation, 1) as ScoreRatio,
    case 
        when u.Reputation is null or u.Reputation < 100 then 'LowRep'
        when u.Reputation between 100 and 1000 then 'MediumRep'
        else 'HighRep'
    end as ReputationCategory,
    array_agg(distinct tt.Tag) filter (where tt.Tag is not null) as FrequentTags
from UserActivity u
left join RankedPosts p on p.OwnerUserId = u.UserId and p.RankByScoreView = 1
left join FilteredQuestions fq on fq.Id = p.Id
left join (
    select Tag from TopTags tt where tt.Tag is not null limit 5
) tt on tt.Tag = any(string_to_array(trim(both '<>' from p.Tags), '><'))
where u.QuestionsAsked > 5 and u.AnswersGiven > 10
order by u.Reputation desc nulls last, p.Score desc nulls last
limit 100;