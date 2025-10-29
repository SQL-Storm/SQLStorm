-- {"query": "2365.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1470} 
with RecursivePostHierarchy as (
    select
        p.Id,
        p.ParentId,
        0 as Level,
        array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only
    union all
    select
        a.Id,
        a.ParentId,
        r.Level + 1,
        r.Path || a.Id
    from Posts a
    join RecursivePostHierarchy r on a.ParentId = r.Id and a.PostTypeId = 2 -- answers only
    where not a.Id = any(r.Path)
),
UserBadgeAgg as (
    select
        b.UserId,
        count(*) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        bool_or(b.TagBased = 1) as HasTagBased
    from Badges b
    group by b.UserId
),
PostLinkDuplicates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate
    group by pl.PostId
),
PostVoteSummary as (
    select
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'AcceptedByOriginator' then 1 else 0 end) as AcceptedVotes,
        count(*) as TotalVotes
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
PostFirstClosedAndReopened as (
    select
        ph.PostId,
        min(case when pht.Name = 'Post Closed' then ph.CreationDate end) as FirstClosedDate,
        min(case when pht.Name = 'Post Reopened' then ph.CreationDate end) as FirstReopenedDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    group by ph.PostId
),
QuestionCommentStats as (
    select
        c.PostId,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(u.DisplayName, c.UserDisplayName) || ': ' || left(c.Text, 30), ' | ') as SampleComments
    from Comments c
    left join Users u on u.Id = c.UserId
    group by c.PostId
),
OwnerActivityWindow as (
    select
        p.OwnerUserId,
        p.Id as QuestionId,
        p.Score,
        p.CreationDate,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RecentPostRank,
        count(*) over (partition by p.OwnerUserId) as TotalPostsByOwner
    from Posts p
    where p.PostTypeId = 1 and p.OwnerUserId is not null
),
RankedQuestions as (
    select
        p.Id,
        p.Title,
        p.ViewCount,
        p.Score,
        p.Tags,
        p.OwnerUserId,
        u.Reputation,
        uba.BadgeCount,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        uba.HasTagBased,
        pls.DuplicateCount,
        pvs.UpVotes,
        pvs.DownVotes,
        pvs.AcceptedVotes,
        pvs.TotalVotes,
        phcr.FirstClosedDate,
        phcr.FirstReopenedDate,
        qc.CommentCount,
        qc.LastCommentDate,
        qc.SampleComments,
        oa.RecentPostRank,
        oa.TotalPostsByOwner,
        -- window function example: running average score for owner's questions
        avg(p.Score) over (partition by p.OwnerUserId order by p.CreationDate rows between unbounded preceding and current row) as RunningAvgScoreByOwner,
        -- complicated expression including NULL logic and string operations
        case 
            when p.ViewCount > 10000 and p.Score > 50 then 'HighImpact'
            when p.ViewCount between 1000 and 10000 and p.Score between 10 and 50 then 'MediumImpact'
            when p.ViewCount < 1000 or p.Score < 10 then 'LowImpact'
            else 'UndefinedImpact'
        end as ImpactCategory,
        -- safe tag count parsed from XML-like tags string, handling NULLs and empty
        coalesce(array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'),1),0) as TagCount
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join UserBadgeAgg uba on uba.UserId = p.OwnerUserId
    left join PostLinkDuplicates pls on pls.PostId = p.Id
    left join PostVoteSummary pvs on pvs.PostId = p.Id
    left join PostFirstClosedAndReopened phcr on phcr.PostId = p.Id
    left join QuestionCommentStats qc on qc.PostId = p.Id
    left join OwnerActivityWindow oa on oa.QuestionId = p.Id
    where p.PostTypeId = 1
),
FinalSelection as (
    select *
    from RankedQuestions
    where BadgeCount >= 10 or (Reputation > 10000 and UpVotes > 100)
    union
    select *
    from RankedQuestions
    where ImpactCategory = 'HighImpact' and DuplicateCount > 5
)
select
    Id,
    Title,
    ViewCount,
    Score,
    ImpactCategory,
    TagCount,
    Reputation,
    BadgeCount,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    HasTagBased,
    DuplicateCount,
    UpVotes,
    DownVotes,
    AcceptedVotes,
    TotalVotes,
    FirstClosedDate,
    FirstReopenedDate,
    CommentCount,
    LastCommentDate,
    SampleComments,
    RecentPostRank,
    TotalPostsByOwner,
    RunningAvgScoreByOwner,
    -- correlated scalar subquery for last edit user display name and edit count on post
    (select u.DisplayName from Users u join PostHistory ph on ph.UserId = u.Id where ph.PostId = RankedQuestions.Id order by ph.CreationDate desc limit 1) as LastEditorDisplayName,
    (select count(*) from PostHistory ph where ph.PostId = RankedQuestions.Id and ph.UserId = RankedQuestions.OwnerUserId) as OwnerEditCount
from FinalSelection RankedQuestions
order by RunningAvgScoreByOwner desc, ViewCount desc
limit 50;